// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockFeed {
    int256 public answer; uint256 public updatedAt; uint256 public startedAt; uint8 public dec;
    constructor(int256 a, uint8 d) { answer = a; dec = d; updatedAt = block.timestamp; startedAt = block.timestamp; }
    function set(int256 a, uint256 u) external { answer = a; updatedAt = u; }
    function setStarted(uint256 s) external { startedAt = s; }
    function decimals() external view returns (uint8) { return dec; }
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, startedAt, updatedAt, 1);
    }
}
