# Demo video — under 3 minutes

**0:00–0:30 Problem (screen: Robinhood docs oracle page)**
"Robinhood Chain gives every tokenized stock a Chainlink price. It doesn't tell your contract the market is
closed, the stock is halted, a split lands tomorrow, the issuer paused the oracle, or that this NVDA is a fake.
The docs even say to check a sequencer uptime feed — which Chainlink doesn't publish for this chain."

**0:30–0:45 One call (screen: IStockGuard.sol)**
"Stock-Hours Guard is one view call: Allow, Warn, or Block, with reason bits. Here's it live on testnet."

**0:45–1:45 Six scenarios (screen: terminal running Demo.s.sol + curl /check, explorer tx list beside it)**
regular → Allow · closed → Warn MARKET_CLOSED · stale (61h feed) → Block FEED_STALE
halt → Block TRADING_HALT (Telegram alert pops) · split → Warn PENDING_CORP_ACT · paused → Block ORACLE_PAUSED
Then: GuardedV3Router swap succeeds in Regular, reverts on halt. Copycat address → Block UNKNOWN_TOKEN.

**1:45–2:20 Sentinels (screen: three terminals — Railway logs, Mac pm2, Termux — then sentinelState())**
"Three sentinels on three providers. Quorum two. Here's the recorded outage: Termux got killed, recovered,
grace ran, cleared. silent=0 recovering=0." Show the explorer heartbeat history.

**2:20–2:45 Keeper history (screen: explorer events on StockGuard)**
"Every session change since Sept 25 is on-chain: Overnight, PreMarket, Regular, PostMarket, Closed."

**2:45–3:00 Roadmap**
"Mainnet with the real roster, external sentinel operators, an L1 sentinel through the delayed inbox,
and lending-market integration. Repo and live API in the description."
