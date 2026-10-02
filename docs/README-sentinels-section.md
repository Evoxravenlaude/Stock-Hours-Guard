<!-- Insert into README.md directly under the "**Sequencer sentinels.**" paragraph -->

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
