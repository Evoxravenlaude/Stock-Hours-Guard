// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {StockGuard} from "../src/StockGuard.sol";
import {IStockGuard} from "../src/interfaces/IStockGuard.sol";
import {MockFeed} from "../src/mocks/MockFeed.sol";
import {MockStockToken} from "../src/mocks/MockStockToken.sol";

/// Drives the testnet mocks through the demo scenarios. Set GUARD, TOKEN, FEED env vars.
///   SCENARIO=halt forge script script/Demo.s.sol --rpc-url $RPC --broadcast --private-key $PK
/// scenarios: regular | closed | halt | stale | split | paused
contract Demo is Script {
    function run() external {
        StockGuard g = StockGuard(vm.envAddress("GUARD"));
        MockStockToken t = MockStockToken(vm.envAddress("TOKEN"));
        MockFeed f = MockFeed(vm.envAddress("FEED"));
        string memory s = vm.envString("SCENARIO");
        bytes32 h = keccak256(bytes(s));
        vm.startBroadcast();
        if (h == keccak256("regular")) {
            f.set(f.answer(), block.timestamp); t.setOraclePaused(false); t.scheduleMultiplier(1e18, 0);
            g.updateStatus(address(t), IStockGuard.Session.Regular, false, true, IStockGuard.Tradability.Tradable);
        } else if (h == keccak256("closed")) {
            g.updateStatus(address(t), IStockGuard.Session.Closed, false, true, IStockGuard.Tradability.Tradable);
        } else if (h == keccak256("halt")) {
            g.updateStatus(address(t), IStockGuard.Session.Regular, true, true, IStockGuard.Tradability.Tradable);
        } else if (h == keccak256("stale")) {
            f.set(f.answer(), block.timestamp - 61 hours);
            g.updateStatus(address(t), IStockGuard.Session.Closed, false, true, IStockGuard.Tradability.Tradable);
        } else if (h == keccak256("split")) {
            t.scheduleMultiplier(4e18, block.timestamp + 6 hours);
        } else if (h == keccak256("paused")) {
            t.setOraclePaused(true);
        }
        vm.stopBroadcast();
        (IStockGuard.Verdict v, uint256 r) = g.check(address(t), 0, 0);
        console.log("scenario:", s);
        console.log("verdict (0 allow,1 warn,2 block):", uint256(v));
        console.log("reason bits:", r);
    }
}
