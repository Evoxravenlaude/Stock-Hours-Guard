// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IStockGuard {
    enum Session { Closed, PreMarket, Regular, PostMarket, Overnight }
    enum Tradability { Unknown, Tradable, Untradable, ClosingOnly, OpeningOnly }
    enum Verdict { Allow, Warn, Block }

    struct AssetStatus {
        string symbol;
        Session session;
        bool halted;
        bool active;
        Tradability tradability;
        uint64 updatedAt;
    }

    /// @notice One call before you trade, lend against, or liquidate a Stock Token.
    /// @param token          Stock Token address.
    /// @param quotedPrice    Price you are about to act on, in the Chainlink feed's decimals (0 to skip).
    /// @param maxDeviationBps Max allowed distance from the Chainlink reference (0 to skip).
    /// @return verdict Allow / Warn / Block.
    /// @return reasons Bitmask of R_* reason codes (see StockGuard).
    function check(address token, uint256 quotedPrice, uint256 maxDeviationBps)
        external view returns (Verdict verdict, uint256 reasons);

    function status(address token) external view returns (AssetStatus memory);
    function registered(address token) external view returns (bool);
    function feedOf(address token) external view returns (address);
}
