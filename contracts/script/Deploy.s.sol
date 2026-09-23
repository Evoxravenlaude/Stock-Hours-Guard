// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {StockGuard} from "../src/StockGuard.sol";

/// forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --private-key $PK
/// Then: cast send $GUARD "registerAsset(address,string,address)" <token> "NVDA" <feed> ...
contract Deploy is Script {
    function run() external {
        vm.startBroadcast();
        StockGuard g = new StockGuard(StockGuard.Config({
            maxFeedAge: 1 hours,
            maxStatusAge: 15 minutes,
            corpActionWindow: 1 days,
            sequencerGrace: 30 minutes,
            sequencerUptimeFeed: address(0) // set once Chainlink publishes one for Robinhood Chain
        }));
        console.log("StockGuard:", address(g));
        vm.stopBroadcast();
    }
}
