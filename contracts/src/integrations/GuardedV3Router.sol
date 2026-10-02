// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IStockGuard} from "../interfaces/IStockGuard.sol";

/// Minimal Uniswap V3 SwapRouter surface (exactInputSingle). Uniswap V3 (SwapRouter02) is deployed on
/// Robinhood Chain mainnet; on testnet this wrapper is deployed against MockV3Router, which implements
/// the same interface. Point the constructor at the real router address for mainnet.
interface ISwapRouterV3 {
    struct ExactInputSingleParams {
        address tokenIn; address tokenOut; uint24 fee; address recipient; uint256 deadline;
        uint256 amountIn; uint256 amountOutMinimum; uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IERC20Min {
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
}

/// @title GuardedV3Router
/// @notice Drop-in wrapper for Uniswap V3 swaps involving a Stock Token. Runs guard.check() on the
/// stock leg with the price implied by the caller's own quote, reverts with reason bits on Block,
/// and emits the warning bits on Warn so bots and front ends can surface them. Targets the Uniswap V3
/// router interface (mainnet SwapRouter02); no hook support required.
contract GuardedV3Router {
    IStockGuard public immutable guard;
    ISwapRouterV3 public immutable router;
    uint256 public immutable maxDeviationBps;

    event Warned(address indexed stockToken, uint256 reasons);
    error GuardBlocked(address stockToken, uint256 reasons);

    constructor(IStockGuard g, ISwapRouterV3 r, uint256 maxBps) { guard = g; router = r; maxDeviationBps = maxBps; }

    /// @param stockToken   Which leg is the Stock Token (tokenIn or tokenOut).
    /// @param impliedPrice Price per share implied by the caller's quote, in the Chainlink feed's decimals.
    function exactInputSingleGuarded(
        ISwapRouterV3.ExactInputSingleParams calldata p,
        address stockToken,
        uint256 impliedPrice
    ) external returns (uint256 amountOut) {
        require(stockToken == p.tokenIn || stockToken == p.tokenOut, "stock leg");
        (IStockGuard.Verdict v, uint256 reasons) = guard.check(stockToken, impliedPrice, maxDeviationBps);
        if (v == IStockGuard.Verdict.Block) revert GuardBlocked(stockToken, reasons);
        if (v == IStockGuard.Verdict.Warn) emit Warned(stockToken, reasons);

        IERC20Min(p.tokenIn).transferFrom(msg.sender, address(this), p.amountIn);
        IERC20Min(p.tokenIn).approve(address(router), p.amountIn);
        amountOut = router.exactInputSingle(p);
    }
}
