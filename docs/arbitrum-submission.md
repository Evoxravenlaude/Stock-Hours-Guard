# Stock-Hours Guard — Arbitrum Open House Singapore submission

**Category:** Promising Products (new financial primitive) — also entered in Open.
**Chain:** Robinhood Chain Testnet (46630), an Arbitrum Orbit chain. Targeting the reserved Robinhood Chain slot.
**Repo:** https://github.com/Evoxravenlaude/Stock-Hours-Guard · **Demo video:** <youtube link> · **Live API:** https://stock-hours-guard-production.up.railway.app/check/<token>

## One line
One call before you touch a tokenized stock: `guard.check(token, price, maxBps)` → Allow / Warn / Block with reasons.

## The problem
Robinhood Chain prices every Stock Token with a Chainlink feed. Nothing on-chain says whether the underlying
market is open, whether the stock is halted, whether a split lands tomorrow, whether the issuer paused the
oracle, or whether the NVDA address you were handed is a copycat. Chains run 24/7; the NYSE does not, and most
tokenized-stock volume happens outside regular hours, exactly when prices go stale and AMM pools drift.
Robinhood's own docs tell builders to check a Chainlink L2 Sequencer Uptime Feed before reading prices.
Chainlink does not publish one for Robinhood Chain and has stopped adding networks.

## What we built (all inside the window, first commit Sept 22)
- **StockGuard.sol** — registry of genuine tokens and feeds; keeper-fed session / halt / tradability status;
  on-chain reads of Chainlink freshness, ERC-8056 `effectiveAt()` for pending corporate actions, and the
  issuer's `oraclePaused()`; 13 reason bits; hard blocks vs warnings.
- **Sentinel quorum** — the sequencer-uptime signal the docs assume exists. M independent sentinels post
  heartbeats; `SEQUENCER_DOWN` is raised while ≥ quorum are silent or inside post-recovery grace. Live as
  2-of-3 across three providers (Railway, macOS, Android/Termux). One real outage/recovery cycle is already in
  the on-chain history.
- **Keeper** — Robinhood REST (`/assets`, `/prices.isTradingHalt`) + NYSE 24/5 calendar → `updateStatusBatch`
  only on change; HTTP mirror; Telegram alerts. Running on Railway since Sept 25 with every session transition
  recorded on-chain.
- **Integrations** — `GuardedV3Router`, a wrapper for the Uniswap V3 SwapRouter interface (V3 is live on
  Robinhood Chain mainnet; deployed on testnet against a mock router with the same interface), and a
  Uniswap v4 `beforeSwap` hook. Example `GuardedVault`. 22 Foundry tests.

## What is honest about it
Testnet has no Stock Tokens, equity feeds, or Uniswap V3 deployment, so the testnet deployment uses mock
tokens, feeds, and a mock V3 router with the exact mainnet interfaces; the Guard, router wrapper, and hook
bytecode are unchanged for mainnet. No mainnet deployment yet. Zero external users; the keeper and all three
sentinels are ours, on three separate providers.

## Milestones (half of prize paid against these)
- **M1 (Oct):** mainnet deployment with the full Robinhood Stock Token roster registered from official sources;
  public status page; two external sentinel operators recruited (ecosystem builders), quorum raised to 3-of-5.
- **M2 (Nov):** L1 sentinel on Ethereum posting status through the delayed inbox, so the flag flips during a
  sequencer outage rather than only after; v4 hook deployed against the first Stock-Token pool.
- **M3 (Dec–Jan):** metered status API for bots (per-call USDC), signed off-chain attestations, first lending
  market integration (stock-token collateral that cannot be liquidated on a stale weekend price).
- **Go-to-market:** every Robinhood Chain protocol that lists Stock Tokens is a customer; we start with DEX
  aggregators and lending markets, who carry the liquidation risk and already read Chainlink.

## Team
<names, roles, one line each>
