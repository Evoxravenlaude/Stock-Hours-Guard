// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IStockGuard} from "../interfaces/IStockGuard.sol";

interface IERC20 {
    function transferFrom(address, address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
}

/// @notice Minimal example: a vault that refuses to value or release Stock Tokens while the
/// guard says Block. Shows the integration surface a lending market or AMM hook would use.
contract GuardedVault {
    IStockGuard public immutable guard;
    uint256 public maxDeviationBps = 150; // 1.5%
    mapping(address => mapping(address => uint256)) public balances;

    event Blocked(address indexed token, uint256 reasons);
    error GuardBlocked(uint256 reasons);

    constructor(IStockGuard g) { guard = g; }

    function deposit(address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        balances[msg.sender][token] += amount;
    }

    /// @dev quotedPrice = the price the caller intends to act on (e.g. a DEX quote), feed decimals.
    function withdrawAtPrice(address token, uint256 amount, uint256 quotedPrice) external {
        (IStockGuard.Verdict v, uint256 reasons) = guard.check(token, quotedPrice, maxDeviationBps);
        if (v == IStockGuard.Verdict.Block) {
            emit Blocked(token, reasons);
            revert GuardBlocked(reasons);
        }
        balances[msg.sender][token] -= amount;
        IERC20(token).transfer(msg.sender, amount);
    }
}
