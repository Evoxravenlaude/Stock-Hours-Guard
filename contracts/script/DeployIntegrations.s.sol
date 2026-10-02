// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IStockGuard} from "../src/interfaces/IStockGuard.sol";
import {GuardedV3Router, ISwapRouterV3} from "../src/integrations/GuardedV3Router.sol";
import {MockV3Router} from "../src/mocks/MockV3Router.sol";

/// Deploys MockV3Router + GuardedV3Router against the already-live StockGuard v2 on testnet.
/// Uses a mock router rather than a real Uniswap V3 deployment: no confirmed Uniswap V3
/// deployment exists on Robinhood Chain testnet (chain 46630) at time of writing -- only
/// mainnet (4663) has a published SwapRouter02 address. Matches this project's existing
/// "testnet mocks mirror mainnet interfaces" framing in docs/arbitrum-submission.md.
contract DeployIntegrations is Script {
    address constant STOCK_GUARD = 0x169197E31D3EE134DFc08d379884eb8B4556b262;
    uint256 constant MAX_DEVIATION_BPS = 150; // 1.5%, matches contracts/test/Integrations.t.sol

    function run() external {
        vm.startBroadcast();

        MockV3Router mockRouter = new MockV3Router();
        console2.log("MockV3Router:", address(mockRouter));

        GuardedV3Router guardedRouter = new GuardedV3Router(
            IStockGuard(STOCK_GUARD),
            ISwapRouterV3(address(mockRouter)),
            MAX_DEVIATION_BPS
        );
        console2.log("GuardedV3Router:", address(guardedRouter));

        vm.stopBroadcast();
    }
}
