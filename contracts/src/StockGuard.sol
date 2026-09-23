// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IStockGuard} from "./interfaces/IStockGuard.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {IScaledUIAmount} from "./interfaces/IScaledUIAmount.sol";

/// @title StockGuard
/// @notice On-chain trading-status registry for tokenized stocks on Robinhood Chain.
///
/// The Chainlink feed for a Stock Token tells you the reference price. It does not tell you
/// whether the underlying market is open, whether the stock is halted, whether a split or
/// dividend multiplier change is about to land, or whether the token address you were handed
/// is the genuine Robinhood contract. StockGuard puts those facts on-chain so any contract
/// (a lending market, an AMM hook, a vault, a bot) can ask one question before acting:
///
///     (verdict, reasons) = guard.check(token, quotedPrice, maxDeviationBps)
///
/// A keeper (see /keeper) reads Robinhood's REST endpoints and the NYSE calendar and writes
/// status updates. The contract itself reads the Chainlink feed, the token's ERC-8056
/// multiplier schedule, and the optional L2 sequencer uptime feed directly, so the parts that
/// can be verified on-chain are.
contract StockGuard is IStockGuard {
    // ----------------------------------------------------------------- reason bits
    uint256 public constant R_UNKNOWN_TOKEN     = 1 << 0; // not in the registry (possible copycat)
    uint256 public constant R_ASSET_INACTIVE    = 1 << 1; // issuer marked asset inactive
    uint256 public constant R_MARKET_CLOSED     = 1 << 2; // underlying market closed (weekend/holiday)
    uint256 public constant R_EXTENDED_HOURS    = 1 << 3; // pre/post/overnight session
    uint256 public constant R_TRADING_HALT      = 1 << 4; // active halt on the underlying
    uint256 public constant R_PENDING_CORP_ACT  = 1 << 5; // multiplier change scheduled within window
    uint256 public constant R_FEED_STALE        = 1 << 6; // Chainlink updatedAt older than maxFeedAge
    uint256 public constant R_FEED_INVALID      = 1 << 7; // answer <= 0 or round incomplete
    uint256 public constant R_PRICE_DEVIATION   = 1 << 8; // quoted price too far from reference
    uint256 public constant R_SEQUENCER_DOWN    = 1 << 9; // L2 sequencer down or in grace period
    uint256 public constant R_STATUS_STALE      = 1 << 10; // keeper has not updated recently
    uint256 public constant R_CLOSING_ONLY      = 1 << 11; // position_closing_only on the underlier
    uint256 public constant R_ORACLE_PAUSED     = 1 << 12; // token.oraclePaused() during a corporate action

    // ----------------------------------------------------------------- storage
    address public owner;
    mapping(address => bool) public isKeeper;

    struct Config {
        uint32 maxFeedAge;         // seconds; feed older than this is stale
        uint32 maxStatusAge;       // seconds; keeper status older than this is stale
        uint32 corpActionWindow;   // seconds before effectiveAt to start flagging
        uint32 sequencerGrace;     // seconds after sequencer comes back before trusting feeds
        address sequencerUptimeFeed; // optional; zero = skip check
    }
    Config public config;

    // Keeper heartbeat doubles as a sequencer-liveness signal: Chainlink does not publish an
    // L2 Sequencer Uptime Feed for Robinhood Chain (and is no longer adding networks), so if the
    // keeper's heartbeats stop for longer than outageThreshold and then resume, we treat that as
    // a recovered outage and apply sequencerGrace before trusting prices again.
    uint64 public lastHeartbeat;
    uint64 public recoveredAt;
    uint32 public outageThreshold = 10 minutes;

    mapping(address => AssetStatus) private _status;
    mapping(address => address) public feedOf;      // token => Chainlink proxy
    mapping(address => bool) public registered;
    address[] private _tokens;

    // ----------------------------------------------------------------- events
    event KeeperSet(address indexed keeper, bool allowed);
    event ConfigSet(Config config);
    event AssetRegistered(address indexed token, string symbol, address feed);
    event Heartbeat(uint64 at, bool recovered);
    event StatusUpdated(address indexed token, Session session, bool halted, bool active, Tradability tradability, uint64 at);

    // ----------------------------------------------------------------- errors
    error NotOwner();
    error NotKeeper();
    error AlreadyRegistered();

    modifier onlyOwner() { if (msg.sender != owner) revert NotOwner(); _; }
    modifier onlyKeeper() { if (!isKeeper[msg.sender] && msg.sender != owner) revert NotKeeper(); _; }

    constructor(Config memory cfg) {
        owner = msg.sender;
        isKeeper[msg.sender] = true;
        config = cfg;
        emit ConfigSet(cfg);
    }

    // ----------------------------------------------------------------- admin
    function setKeeper(address keeper, bool allowed) external onlyOwner {
        isKeeper[keeper] = allowed;
        emit KeeperSet(keeper, allowed);
    }

    function setConfig(Config calldata cfg) external onlyOwner {
        config = cfg;
        emit ConfigSet(cfg);
    }

    /// @notice Register a genuine Robinhood Stock Token and its Chainlink feed proxy.
    /// Addresses must come from docs.robinhood.com/chain/contracts and Chainlink's feed list.
    function registerAsset(address token, string calldata symbol, address feed) external onlyOwner {
        if (registered[token]) revert AlreadyRegistered();
        registered[token] = true;
        feedOf[token] = feed;
        _tokens.push(token);
        _status[token].symbol = symbol;
        _status[token].active = true;
        emit AssetRegistered(token, symbol, feed);
    }

    // ----------------------------------------------------------------- keeper
    function setOutageThreshold(uint32 t) external onlyOwner { outageThreshold = t; }

    /// @notice Call on every keeper tick. A gap longer than outageThreshold marks a recovery.
    function heartbeat() public onlyKeeper {
        bool recovered = lastHeartbeat != 0 && block.timestamp - lastHeartbeat > outageThreshold;
        if (recovered) recoveredAt = uint64(block.timestamp);
        lastHeartbeat = uint64(block.timestamp);
        emit Heartbeat(lastHeartbeat, recovered);
    }

    function updateStatus(
        address token,
        Session session,
        bool halted,
        bool active,
        Tradability tradability
    ) external onlyKeeper {
        heartbeat();
        require(registered[token], "unregistered");
        AssetStatus storage s = _status[token];
        s.session = session;
        s.halted = halted;
        s.active = active;
        s.tradability = tradability;
        s.updatedAt = uint64(block.timestamp);
        emit StatusUpdated(token, session, halted, active, tradability, s.updatedAt);
    }

    /// @notice Batch variant so one keeper tx can refresh the whole roster.
    function updateStatusBatch(
        address[] calldata tokenList,
        Session[] calldata sessions,
        bool[] calldata halted,
        bool[] calldata active,
        Tradability[] calldata tradability
    ) external onlyKeeper {
        heartbeat();
        uint256 n = tokenList.length;
        require(sessions.length == n && halted.length == n && active.length == n && tradability.length == n, "len");
        for (uint256 i; i < n; ++i) {
            require(registered[tokenList[i]], "unregistered");
            AssetStatus storage s = _status[tokenList[i]];
            s.session = sessions[i];
            s.halted = halted[i];
            s.active = active[i];
            s.tradability = tradability[i];
            s.updatedAt = uint64(block.timestamp);
            emit StatusUpdated(tokenList[i], sessions[i], halted[i], active[i], tradability[i], s.updatedAt);
        }
    }

    // ----------------------------------------------------------------- views
    function status(address token) external view returns (AssetStatus memory) {
        return _status[token];
    }

    function tokens() external view returns (address[] memory) {
        return _tokens;
    }

    /// @inheritdoc IStockGuard
    function check(address token, uint256 quotedPrice, uint256 maxDeviationBps)
        public
        view
        returns (Verdict verdict, uint256 reasons)
    {
        if (!registered[token]) {
            return (Verdict.Block, R_UNKNOWN_TOKEN);
        }
        AssetStatus memory s = _status[token];
        Config memory c = config;

        // ---- keeper-supplied status
        if (!s.active) reasons |= R_ASSET_INACTIVE;
        if (s.halted) reasons |= R_TRADING_HALT;
        if (s.session == Session.Closed) reasons |= R_MARKET_CLOSED;
        else if (s.session != Session.Regular) reasons |= R_EXTENDED_HOURS;
        if (s.tradability == Tradability.ClosingOnly) reasons |= R_CLOSING_ONLY;
        if (s.updatedAt == 0 || block.timestamp - s.updatedAt > c.maxStatusAge) reasons |= R_STATUS_STALE;

        // ---- on-chain: pending corporate action (ERC-8056 schedule)
        (bool ok, uint256 effectiveAt) = _pendingCorpAction(token);
        if (ok && effectiveAt > block.timestamp && effectiveAt - block.timestamp <= c.corpActionWindow) {
            reasons |= R_PENDING_CORP_ACT;
        }

        // ---- on-chain: oracle pause flag (advisory, set by the issuer during corporate actions)
        if (_oraclePaused(token)) reasons |= R_ORACLE_PAUSED;

        // ---- on-chain: sequencer (Chainlink feed if one exists, else keeper-heartbeat recovery grace)
        if (c.sequencerUptimeFeed != address(0)) {
            if (!_sequencerHealthy(c)) reasons |= R_SEQUENCER_DOWN;
        } else if (recoveredAt != 0 && block.timestamp - recoveredAt < c.sequencerGrace) {
            reasons |= R_SEQUENCER_DOWN;
        }

        // ---- on-chain: Chainlink reference price
        (int256 answer, uint256 updatedAt, uint8 dec, bool feedOk) = _readFeed(feedOf[token]);
        if (!feedOk || answer <= 0 || updatedAt == 0) {
            reasons |= R_FEED_INVALID;
        } else {
            if (block.timestamp - updatedAt > c.maxFeedAge) reasons |= R_FEED_STALE;
            if (quotedPrice != 0 && maxDeviationBps != 0) {
                uint256 ref = uint256(answer);
                // normalise quotedPrice to feed decimals if caller passes 18-dp; caller documents decimals
                uint256 diff = quotedPrice > ref ? quotedPrice - ref : ref - quotedPrice;
                if (diff * 10_000 > ref * maxDeviationBps) reasons |= R_PRICE_DEVIATION;
            }
            dec; // decimals returned for callers via referencePrice(); unused here
        }

        verdict = _verdict(reasons);
    }

    /// @notice Convenience: Chainlink reference price and decimals for a registered token.
    function referencePrice(address token) external view returns (int256 answer, uint256 updatedAt, uint8 decimals_) {
        bool ok;
        (answer, updatedAt, decimals_, ok) = _readFeed(feedOf[token]);
        require(ok, "feed");
    }

    // ----------------------------------------------------------------- internals
    /// Hard blocks vs soft warnings. Callers can still branch on individual bits.
    function _verdict(uint256 r) internal pure returns (Verdict) {
        uint256 hard = R_UNKNOWN_TOKEN | R_ASSET_INACTIVE | R_TRADING_HALT | R_FEED_INVALID
            | R_SEQUENCER_DOWN | R_PRICE_DEVIATION | R_FEED_STALE | R_ORACLE_PAUSED;
        if (r & hard != 0) return Verdict.Block;
        if (r != 0) return Verdict.Warn;
        return Verdict.Allow;
    }

    function _pendingCorpAction(address token) internal view returns (bool ok, uint256 effectiveAt) {
        (bool s1, bytes memory d1) = token.staticcall(abi.encodeWithSelector(IScaledUIAmount.effectiveAt.selector));
        if (!s1 || d1.length < 32) return (false, 0);
        effectiveAt = abi.decode(d1, (uint256));
        ok = true;
    }

    function _oraclePaused(address token) internal view returns (bool) {
        (bool ok, bytes memory d) = token.staticcall(abi.encodeWithSignature("oraclePaused()"));
        if (!ok || d.length < 32) return false;
        return abi.decode(d, (bool));
    }

    function _readFeed(address feed) internal view returns (int256 answer, uint256 updatedAt, uint8 dec, bool ok) {
        if (feed == address(0)) return (0, 0, 0, false);
        (bool s1, bytes memory d1) = feed.staticcall(abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector));
        if (!s1 || d1.length < 160) return (0, 0, 0, false);
        (, answer,, updatedAt,) = abi.decode(d1, (uint80, int256, uint256, uint256, uint80));
        (bool s2, bytes memory d2) = feed.staticcall(abi.encodeWithSelector(AggregatorV3Interface.decimals.selector));
        dec = (s2 && d2.length >= 32) ? uint8(abi.decode(d2, (uint256))) : 8;
        ok = true;
    }

    /// Chainlink L2 sequencer uptime feed convention: answer 0 = up, 1 = down;
    /// startedAt = time the current status began. Wait sequencerGrace after recovery.
    function _sequencerHealthy(Config memory c) internal view returns (bool) {
        (bool s1, bytes memory d1) = c.sequencerUptimeFeed.staticcall(
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector)
        );
        if (!s1 || d1.length < 160) return false;
        (, int256 answer, uint256 startedAt,,) = abi.decode(d1, (uint80, int256, uint256, uint256, uint80));
        if (answer != 0) return false;
        if (block.timestamp - startedAt < c.sequencerGrace) return false;
        return true;
    }
}
