// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {ISwapRouterV3} from "../integrations/GuardedV3Router.sol";

interface IERC20M { function transferFrom(address,address,uint256) external returns (bool); function transfer(address,uint256) external returns (bool); function mint(address,uint256) external; }

/// Pays out 1:1 for tests.
contract MockV3Router is ISwapRouterV3 {
    uint256 public swaps;
    function exactInputSingle(ExactInputSingleParams calldata p) external payable returns (uint256) {
        IERC20M(p.tokenIn).transferFrom(msg.sender, address(this), p.amountIn);
        IERC20M(p.tokenOut).mint(p.recipient, p.amountIn);
        swaps++;
        return p.amountIn;
    }
}
