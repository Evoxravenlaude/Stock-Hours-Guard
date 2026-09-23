// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {StockGuard} from "../src/StockGuard.sol";
import {IStockGuard} from "../src/interfaces/IStockGuard.sol";
import {GuardedVault} from "../src/examples/GuardedVault.sol";
import {MockFeed} from "../src/mocks/MockFeed.sol";
import {MockStockToken} from "../src/mocks/MockStockToken.sol";

/// Robinhood Chain Testnet (46630) has no Stock Tokens or Chainlink equity feeds deployed,
/// so this script stands up the Guard plus mock NVDA / AAPL / TSLA tokens and feeds that
/// mirror the mainnet interfaces (ERC-20 + ERC-8056 + AggregatorV3), registers them, and
/// deploys the example GuardedVault. Mainnet uses script/Deploy.s.sol + registry/ instead.
///
///   forge script script/DeployTestnet.s.sol \
///     --rpc-url https://rpc.testnet.chain.robinhood.com --broadcast --private-key $PK
contract DeployTestnet is Script {
    function run() external {
        vm.startBroadcast();

        StockGuard g = new StockGuard(StockGuard.Config({
            maxFeedAge: 1 hours,
            maxStatusAge: 15 minutes,
            corpActionWindow: 1 days,
            sequencerGrace: 30 minutes,
            sequencerUptimeFeed: address(0)
        }));

        string[3] memory syms = ["NVDA", "AAPL", "TSLA"];
        int256[3] memory px = [int256(180_00000000), int256(230_00000000), int256(410_00000000)];
        address[3] memory toks;
        for (uint256 i; i < 3; ++i) {
            MockStockToken t = new MockStockToken(string.concat(syms[i], " \u2022 Robinhood Token (testnet mock)"), syms[i]);
            MockFeed f = new MockFeed(px[i], 8);
            g.registerAsset(address(t), syms[i], address(f));
            t.mint(msg.sender, 1_000e18);
            toks[i] = address(t);
            console.log(syms[i], "token:", address(t));
            console.log(syms[i], "feed: ", address(f));
        }

        // seed an initial status so check() is meaningful before the keeper's first tick
        for (uint256 i; i < 3; ++i) {
            g.updateStatus(toks[i], IStockGuard.Session.Regular, false, true, IStockGuard.Tradability.Tradable);
        }

        GuardedVault v = new GuardedVault(g);
        console.log("StockGuard:  ", address(g));
        console.log("GuardedVault:", address(v));
        vm.stopBroadcast();
    }
}
