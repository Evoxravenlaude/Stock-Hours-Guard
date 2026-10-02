# Stock-Hours Guard

**One call before you touch a tokenized stock.**

Robinhood Chain gives every Stock Token a Chainlink price. It does not tell your contract whether the
underlying market is open, whether the stock is halted, whether a split is about to change the multiplier,
or whether the token address you were handed is the real one. Chains run 24/7; the NYSE does not.
Most tokenized-stock volume happens outside regular hours — exactly when reference prices go stale and
AMM prices drift.

Stock-Hours Guard is an on-chain status registry plus a keeper. Any contract (lending market, AMM hook,
vault, liquidation bot) asks one question:

```solidity
(IStockGuard.Verdict v, uint256 reasons) = guard.check(token, quotedPrice, maxDeviationBps);
```

and gets `Allow / Warn / Block` with a reason bitmask:

| bit | reason | source |
|---|---|---|
| 0 | UNKNOWN_TOKEN — not a registered Robinhood Stock Token (copycat guard) | registry |
| 1 | ASSET_INACTIVE | Robinhood `/assets.status` |
| 2 | MARKET_CLOSED — weekend / NYSE holiday | keeper calendar |
| 3 | EXTENDED_HOURS — pre / post / overnight session | keeper calendar |
| 4 | TRADING_HALT | Robinhood `/prices.isTradingHalt` |
| 5 | PENDING_CORP_ACT — multiplier change scheduled inside window | on-chain ERC-8056 `effectiveAt()` |
| 6 | FEED_STALE — Chainlink `updatedAt` too old | on-chain |
| 7 | FEED_INVALID | on-chain |
| 8 | PRICE_DEVIATION — your quote vs Chainlink reference | on-chain |
| 9 | SEQUENCER_DOWN — L2 sequencer down or in grace period | on-chain (optional feed) |
| 10 | STATUS_STALE — keeper hasn't reported recently | on-chain |
| 11 | CLOSING_ONLY — underlier is position-closing-only | Robinhood `/assets.tradingCapabilities` |
| 12 | ORACLE_PAUSED — issuer paused the feed during a corporate action | on-chain `oraclePaused()` |

Hard blocks: unknown token, inactive, halt, invalid/stale feed, oracle paused, sequencer down, price deviation.

**Sequencer sentinels.** Robinhood's docs recommend a Chainlink L2 Sequencer Uptime Feed, but Chainlink does
not list one for Robinhood Chain and has stopped adding networks. StockGuard fills the gap with a sentinel
quorum: M independent sentinels post `heartbeat()` every few minutes. A sentinel that goes silent longer
than `outageThreshold` and then resumes records a recovery. `check()` raises `SEQUENCER_DOWN` while at least
`quorum` sentinels are unhealthy (silent, or recovered inside the last `sequencerGrace` seconds). One dead
or malicious sentinel cannot fake or hide an outage. Run one with `npm run sentinel`; the owner registers it
with `setSentinel(addr, true)` and sets `setQuorum(q, threshold)`. If Chainlink ever ships a feed, set
`sequencerUptimeFeed` and the contract uses it instead. Milestone 2 adds an L1 sentinel that posts status
through the Sepolia/Ethereum delayed inbox so the flag flips *during* an outage, not only after.
Everything else is a warning callers can branch on.

### Live sentinel set (testnet, chain 46630)

Rule: the quorum must be larger than the number of sentinels on any single provider, otherwise one
hosting incident reads as a chain outage. This deployment is 2-of-3 across three providers.

| # | Sentinel | Host / provider | Role |
|---|---|---|---|
| 1 | `0x0D8FafA10024A45B0Edb86bA5cB716A9DF997036` | Railway | keeper (status writes + heartbeat) |
| 2 | `0xA91292A59416cDD46B83850748307c4B18180899` | macOS, pm2 + launchd | sentinel |
| 3 | `0x16aD8a1550D2b027cC1A235AADd07aab355a0393` | Android / Termux, tmux + wake-lock | sentinel |

`setQuorum(2, 900)`: a sentinel is unhealthy after 15 minutes of silence (4-minute cadence, two missed
beats of slack); `SEQUENCER_DOWN` is raised while two or more are silent or inside the 30-minute
post-recovery grace. The heartbeat history for each address is public on the testnet explorer.
Timers are per sentinel: a flapping sentinel only ever counts as one unhealthy sentinel, and a second
genuine outage inside the grace window restarts the clock for the sentinels that observed it.

StockGuard v2: `0x169197E31D3EE134DFc08d379884eb8B4556b262` · deploy tx
`0x4563cda4dcc03a0e70a3e52d7ba50276e1abdab6d216219a60aeda480fafaf3e` · see `DEPLOY.md`.

### Integrations (`contracts/src/integrations/`)

- `GuardedV3Router.sol` — wrapper for the Uniswap V3 SwapRouter interface (V3 is live on Robinhood Chain
  mainnet; the testnet deployment is wired to `MockV3Router`, same interface). Runs `check()` on
  the stock leg with the caller's implied price; reverts on Block, emits `Warned(reasons)` on Warn.
- `StockGuardHook.sol` — Uniswap v4 `beforeSwap` hook: pools containing a registered Stock Token
  refuse swaps while the guard says Block (halt, oracle pause, stale weekend feed, sequencer, copycat).

## Layout

```
contracts/   Foundry. StockGuard.sol (registry + check), integrations/ (V3 router wrapper, v4 hook), example GuardedVault, mocks, 22 tests
keeper/      Node/TS. Robinhood REST + NYSE calendar → updateStatusBatch(); heartbeat timer; HTTP mirror + Telegram alerts
             src/sentinel.ts — standalone heartbeat-only sentinel for other operators
registry/    Genuine token + feed addresses (built only from official sources)
```

## Run

```bash
# contracts
cd contracts && forge test
forge script script/Deploy.s.sol --rpc-url https://rpc.testnet.chain.robinhood.com --broadcast --private-key $PK

# register assets (owner)
cd ../keeper && npm i && cp .env.example .env   # fill GUARD_ADDRESS, KEEPER_PRIVATE_KEY
npx tsx scripts/register.ts ../registry/assets.46630.json

# keeper (omit KEEPER_PRIVATE_KEY for dry-run; API still serves)
npm run dev
curl localhost:8787/check/0xTOKEN?price=18000000000&maxBps=150
```

Chain IDs: mainnet 4663, testnet 46630. Public RPC: `https://rpc.{mainnet,testnet}.chain.robinhood.com`.

## Demo script (for the video)

1. Friday 16:05 ET: `check(NVDA)` → `Warn: EXTENDED_HOURS`.
2. Saturday: Chainlink feed 40h old → `Block: MARKET_CLOSED | FEED_STALE`. GuardedVault refuses a withdrawal at a 6% off-reference quote.
3. Keeper marks a halt from `/prices.isTradingHalt` → `Block: TRADING_HALT`. Telegram alert fires.
4. Schedule a 4:1 split on the token (`effectiveAt` tomorrow) → `Warn: PENDING_CORP_ACT`.
5. Pass a copycat "NVDA" address → `Block: UNKNOWN_TOKEN`.

## Roadmap / milestones

- M1 (hackathon): testnet deploy, full roster registered, keeper live, example consumer.
- M2: mainnet deploy; Chainlink sequencer-uptime feed wired when published for Robinhood Chain; Uniswap v4 hook example.
- M3: metered API + signed off-chain attestations for bots; integrations with one lending market and one AMM.

## What is new for the Arbitrum Open House window

Everything in this repo was started on 2026-09-22 inside the buildathon window. No prior code.
