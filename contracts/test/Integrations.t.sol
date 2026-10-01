// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StockGuard} from "../src/StockGuard.sol";
import {IStockGuard} from "../src/interfaces/IStockGuard.sol";
import {GuardedV3Router, ISwapRouterV3} from "../src/integrations/GuardedV3Router.sol";
import {StockGuardHook, PoolKey, SwapParams} from "../src/integrations/StockGuardHook.sol";
import {MockFeed} from "../src/mocks/MockFeed.sol";
import {MockStockToken} from "../src/mocks/MockStockToken.sol";
import {MockV3Router} from "../src/mocks/MockV3Router.sol";

contract IntegrationsTest is Test {
    StockGuard guard; MockFeed feed; MockStockToken nvda; MockStockToken usdc;
    MockV3Router v3; GuardedV3Router gr; StockGuardHook hook;
    address pm = address(0x9001);

    function setUp() public {
        vm.warp(1_800_000_000);
        guard = new StockGuard(StockGuard.Config({maxFeedAge: 1 hours, maxStatusAge: 10 minutes,
            corpActionWindow: 1 days, sequencerGrace: 30 minutes, sequencerUptimeFeed: address(0)}));
        feed = new MockFeed(180_00000000, 8);
        nvda = new MockStockToken("NVDA", "NVDA"); usdc = new MockStockToken("USDC", "USDC");
        guard.registerAsset(address(nvda), "NVDA", address(feed));
        guard.updateStatus(address(nvda), IStockGuard.Session.Regular, false, true, IStockGuard.Tradability.Tradable);
        v3 = new MockV3Router(); gr = new GuardedV3Router(guard, v3, 150); hook = new StockGuardHook(guard, pm);
        usdc.mint(address(this), 1_000e6); usdc.approve(address(gr), type(uint256).max);
    }

    function _params() internal view returns (ISwapRouterV3.ExactInputSingleParams memory) {
        return ISwapRouterV3.ExactInputSingleParams(address(usdc), address(nvda), 3000, address(this), block.timestamp + 60, 180e6, 0, 0);
    }

    function test_router_swaps_in_regular_session() public {
        uint256 out = gr.exactInputSingleGuarded(_params(), address(nvda), 180_00000000);
        assertEq(out, 180e6); assertEq(v3.swaps(), 1);
    }

    function test_router_reverts_on_halt() public {
        guard.updateStatus(address(nvda), IStockGuard.Session.Regular, true, true, IStockGuard.Tradability.Tradable);
        vm.expectRevert(abi.encodeWithSelector(GuardedV3Router.GuardBlocked.selector, address(nvda), guard.R_TRADING_HALT()));
        gr.exactInputSingleGuarded(_params(), address(nvda), 180_00000000);
        assertEq(v3.swaps(), 0);
    }

    function test_router_reverts_on_off_reference_quote() public {
        vm.expectRevert(abi.encodeWithSelector(GuardedV3Router.GuardBlocked.selector, address(nvda), guard.R_PRICE_DEVIATION()));
        gr.exactInputSingleGuarded(_params(), address(nvda), 195_00000000); // 8.3% off
    }

    function test_router_warns_but_swaps_after_hours() public {
        guard.updateStatus(address(nvda), IStockGuard.Session.PostMarket, false, true, IStockGuard.Tradability.Tradable);
        vm.expectEmit(true, false, false, true);
        emit GuardedV3Router.Warned(address(nvda), guard.R_EXTENDED_HOURS());
        gr.exactInputSingleGuarded(_params(), address(nvda), 180_00000000);
        assertEq(v3.swaps(), 1);
    }

    function test_hook_allows_then_blocks() public {
        PoolKey memory key = PoolKey(address(usdc), address(nvda), 3000, 60, address(hook));
        SwapParams memory sp = SwapParams(true, -1e6, 0);
        vm.prank(pm);
        (bytes4 sel,,) = hook.beforeSwap(address(this), key, sp, "");
        assertEq(sel, hook.BEFORE_SWAP_SELECTOR());
        nvda.setOraclePaused(true);
        vm.expectRevert(abi.encodeWithSelector(StockGuardHook.GuardBlocked.selector, address(nvda), guard.R_ORACLE_PAUSED()));
        vm.prank(pm);
        hook.beforeSwap(address(this), key, sp, "");
    }

    function test_hook_rejects_non_manager() public {
        PoolKey memory key = PoolKey(address(usdc), address(nvda), 3000, 60, address(hook));
        vm.expectRevert(StockGuardHook.NotPoolManager.selector);
        hook.beforeSwap(address(this), key, SwapParams(true, -1, 0), "");
    }
}
