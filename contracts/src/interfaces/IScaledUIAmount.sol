// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// ERC-8056 (Scaled UI Amount) surface used by Robinhood Stock Tokens.
interface IScaledUIAmount {
    function uiMultiplier() external view returns (uint256);
    function newUIMultiplier() external view returns (uint256);
    function effectiveAt() external view returns (uint256);
    function balanceOfUI(address account) external view returns (uint256);
    function totalSupplyUI() external view returns (uint256);
    event UIMultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier, uint256 effectiveAtTimestamp);
}
