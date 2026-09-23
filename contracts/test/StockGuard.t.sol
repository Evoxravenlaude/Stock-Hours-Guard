// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StockGuard} from "../src/StockGuard.sol";
import {IStockGuard} from "../src/interfaces/IStockGuard.sol";
import {GuardedVault} from "../src/examples/GuardedVault.sol";
import {MockFeed} from "../src/mocks/MockFeed.sol";
import {MockStockToken} from "../src/mocks/MockStockToken.sol";

contract StockGuardTest is Test {
    StockGuard guard;
    MockFeed feed;
    MockFeed seq;
    MockStockToken nvda;
    MockStockToken fake;
    GuardedVault vault;
    address keeper = address(0xBEEF);

    function setUp() public {
        vm.warp(1_800_000_000);
        seq = new MockFeed(0, 0); // sequencer up
        seq.setStarted(block.timestamp - 1 days);
        guard = new StockGuard(StockGuard.Config({
            maxFeedAge: 1 hours,
            maxStatusAge: 10 minutes,
            corpActionWindow: 1 days,
            sequencerGrace: 30 minutes,
            sequencerUptimeFeed: address(seq)
        }));
        feed = new MockFeed(180_00000000, 8); // $180.00
        nvda = new MockStockToken("NVIDIA Robinhood Token", "NVDA");
        fake = new MockStockToken("NVIDIA Robinhood Token", "NVDA"); // copycat
        guard.registerAsset(address(nvda), "NVDA", address(feed));
        guard.setKeeper(keeper, true);
        vault = new GuardedVault(guard);
        _regular();
    }

    function _regular() internal {
        vm.prank(keeper);
        guard.updateStatus(address(nvda), IStockGuard.Session.Regular, false, true, IStockGuard.Tradability.Tradable);
    }

    function test_allow_in_regular_session() public view {
        (IStockGuard.Verdict v, uint256 r) = guard.check(address(nvda), 180_00000000, 100);
        assertEq(uint256(v), uint256(IStockGuard.Verdict.Allow));
        assertEq(r, 0);
    }

    function test_block_unknown_token() public view {
        (IStockGuard.Verdict v, uint256 r) = guard.check(address(fake), 0, 0);
        assertEq(uint256(v), uint256(IStockGuard.Verdict.Block));
        assertEq(r, guard.R_UNKNOWN_TOKEN());
    }

    function test_warn_market_closed() public {
        vm.prank(keeper);
        guard.updateStatus(address(nvda), IStockGuard.Session.Closed, false, true, IStockGuard.Tradability.Tradable);
        (IStockGuard.Verdict v, uint256 r) = guard.check(address(nvda), 0, 0);
        assertEq(uint256(v), uint256(IStockGuard.Verdict.Warn));
        assertTrue(r & guard.R_MARKET_CLOSED() != 0);
    }

    function test_block_halt() public {
        vm.prank(keeper);
        guard.updateStatus(address(nvda), IStockGuard.Session.Regular, true, true, IStockGuard.Tradability.Tradable);
        (IStockGuard.Verdict v, uint256 r) = guard.check(address(nvda), 0, 0);
        assertEq(uint256(v), uint256(IStockGuard.Verdict.Block));
        assertTrue(r & guard.R_TRADING_HALT() != 0);
    }

    function test_block_stale_feed_over_weekend() public {
        // Friday close price, then 61 hours pass (Sunday night)
        feed.set(180_00000000, block.timestamp);
        vm.warp(block.timestamp + 61 hours);
        vm.prank(keeper);
        guard.updateStatus(address(nvda), IStockGuard.Session.Closed, false, true, IStockGuard.Tradability.Tradable);
        (IStockGuard.Verdict v, uint256 r) = guard.check(address(nvda), 0, 0);
        assertEq(uint256(v), uint256(IStockGuard.Verdict.Block));
        assertTrue(r & guard.R_FEED_STALE() != 0);
        assertTrue(r & guard.R_MARKET_CLOSED() != 0);
    }

    function test_block_price_deviation() public view {
        // quote $190 vs reference $180 = 5.5% > 1.5%
        (IStockGuard.Verdict v, uint256 r) = guard.check(address(nvda), 190_00000000, 150);
        assertEq(uint256(v), uint256(IStockGuard.Verdict.Block));
        assertTrue(r & guard.R_PRICE_DEVIATION() != 0);
    }

    function test_warn_pending_split() public {
        nvda.scheduleMultiplier(4e18, block.timestamp + 6 hours); // 4:1 split tomorrow
        (IStockGuard.Verdict v, uint256 r) = guard.check(address(nvda), 0, 0);
        assertEq(uint256(v), uint256(IStockGuard.Verdict.Warn));
        assertTrue(r & guard.R_PENDING_CORP_ACT() != 0);
    }

    function test_block_sequencer_down_and_grace() public {
        seq.set(1, block.timestamp); // down
        (IStockGuard.Verdict v, uint256 r) = guard.check(address(nvda), 0, 0);
        assertEq(uint256(v), uint256(IStockGuard.Verdict.Block));
        assertTrue(r & guard.R_SEQUENCER_DOWN() != 0);
        // back up 5 minutes ago: still inside grace period
        seq.set(0, block.timestamp); seq.setStarted(block.timestamp - 5 minutes);
        (, r) = guard.check(address(nvda), 0, 0);
        assertTrue(r & guard.R_SEQUENCER_DOWN() != 0);
        // back up 1 hour ago: healthy
        seq.setStarted(block.timestamp - 1 hours);
        (, r) = guard.check(address(nvda), 0, 0);
        assertTrue(r & guard.R_SEQUENCER_DOWN() == 0);
    }

    function test_warn_keeper_stale() public {
        vm.warp(block.timestamp + 11 minutes);
        feed.set(180_00000000, block.timestamp);
        (IStockGuard.Verdict v, uint256 r) = guard.check(address(nvda), 0, 0);
        assertEq(uint256(v), uint256(IStockGuard.Verdict.Warn));
        assertTrue(r & guard.R_STATUS_STALE() != 0);
    }

    function test_vault_reverts_when_blocked() public {
        nvda.mint(address(this), 10e18);
        nvda.approve(address(vault), 10e18);
        vault.deposit(address(nvda), 10e18);
        vm.prank(keeper);
        guard.updateStatus(address(nvda), IStockGuard.Session.Regular, true, true, IStockGuard.Tradability.Tradable);
        vm.expectRevert(abi.encodeWithSelector(GuardedVault.GuardBlocked.selector, guard.R_TRADING_HALT()));
        vault.withdrawAtPrice(address(nvda), 1e18, 180_00000000);
        _regular();
        vault.withdrawAtPrice(address(nvda), 1e18, 180_00000000);
        assertEq(nvda.balanceOf(address(this)), 1e18);
    }

    function test_block_oracle_paused() public {
        nvda.setOraclePaused(true);
        (IStockGuard.Verdict v, uint256 r) = guard.check(address(nvda), 0, 0);
        assertEq(uint256(v), uint256(IStockGuard.Verdict.Block));
        assertTrue(r & guard.R_ORACLE_PAUSED() != 0);
    }

    function test_heartbeat_gap_triggers_recovery_grace() public {
        // no Chainlink sequencer feed: rely on keeper heartbeat
        guard.setConfig(StockGuard.Config({maxFeedAge: 1 hours, maxStatusAge: 10 minutes, corpActionWindow: 1 days,
            sequencerGrace: 30 minutes, sequencerUptimeFeed: address(0)}));
        _regular(); // heartbeat at t0
        vm.warp(block.timestamp + 45 minutes); // > outageThreshold gap
        feed.set(180_00000000, block.timestamp);
        _regular(); // heartbeat resumes: recovery recorded
        (IStockGuard.Verdict v, uint256 r) = guard.check(address(nvda), 0, 0);
        assertEq(uint256(v), uint256(IStockGuard.Verdict.Block));
        assertTrue(r & guard.R_SEQUENCER_DOWN() != 0);
        // keep heartbeating every 5 minutes through the grace window
        for (uint256 i; i < 7; ++i) { vm.warp(block.timestamp + 5 minutes); feed.set(180_00000000, block.timestamp); _regular(); }
        (, r) = guard.check(address(nvda), 0, 0);
        assertTrue(r & guard.R_SEQUENCER_DOWN() == 0);
    }

    function test_only_keeper_can_update() public {
        vm.expectRevert(StockGuard.NotKeeper.selector);
        vm.prank(address(0xBAD));
        guard.updateStatus(address(nvda), IStockGuard.Session.Regular, false, true, IStockGuard.Tradability.Tradable);
    }
}
