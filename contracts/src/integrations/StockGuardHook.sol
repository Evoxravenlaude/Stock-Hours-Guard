// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IStockGuard} from "../interfaces/IStockGuard.sol";

/// Uniswap v4 hook surface, declared locally so the repo stays dependency-light. Mirrors
/// IHooks.beforeSwap and the PoolKey / SwapParams structs from v4-core; swap in the real
/// imports and the BaseHook address-mining when deploying against a live v4 PoolManager.
interface IPoolManagerLike {}
struct Currency { address addr; }
struct PoolKey { address currency0; address currency1; uint24 fee; int24 tickSpacing; address hooks; }
struct SwapParams { bool zeroForOne; int256 amountSpecified; uint160 sqrtPriceLimitX96; }

/// @title StockGuardHook
/// @notice v4 beforeSwap hook: a pool that includes a registered Stock Token refuses swaps while the
/// guard says Block. Deviation is left to the pool's own price (sqrtPriceLimit) so the hook only
/// enforces status bits: halt, closed+stale feed, oracle pause, sequencer, copycat.
contract StockGuardHook {
    IStockGuard public immutable guard;
    address public immutable poolManager;
    bytes4 public constant BEFORE_SWAP_SELECTOR = StockGuardHook.beforeSwap.selector;

    error GuardBlocked(address stockToken, uint256 reasons);
    error NotPoolManager();

    constructor(IStockGuard g, address pm) { guard = g; poolManager = pm; }

    function beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata)
        external view returns (bytes4, int256, uint24)
    {
        if (msg.sender != poolManager) revert NotPoolManager();
        _enforce(key.currency0);
        _enforce(key.currency1);
        return (BEFORE_SWAP_SELECTOR, 0, 0);
    }

    function _enforce(address token) internal view {
        if (!guard.registered(token)) return; // not a stock leg (e.g. USDC); nothing to enforce
        (IStockGuard.Verdict v, uint256 reasons) = guard.check(token, 0, 0);
        if (v == IStockGuard.Verdict.Block) revert GuardBlocked(token, reasons);
    }
}
