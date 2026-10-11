# Stock-Hours Guard — Colosseum Crypto World's Fair submission

Due October 12, 2026, 11:59pm PT. Submit in the Colosseum Arena (register link: https://colosseum.com/arena/hackathon/register?entry=worldsfair). Fill the fields from the sections below; the form's exact field names may differ.

**Project name:** Stock-Hours Guard

**One line:** One call before you touch a tokenized stock: `guard.check(token, price, maxBps)` → Allow / Warn / Block, with reasons.

**Tracks:** Robinhood Chain (ecosystem track). Also tick any regional track open to Nigeria (Superteam Nigeria) and the University Prize if the form asks whether you are a student.

**Repo:** https://github.com/Evoxravenlaude/Stock-Hours-Guard (MIT)
**Demo video (2:59):** https://youtu.be/w-wEHWruzVM
**Live API:** https://stock-hours-guard-production.up.railway.app/check/0xcc2e5173B4b7A025536991be893AE5945A3ba144
**Contract (Robinhood Chain testnet, 46630):** StockGuard v2 `0x169197E31D3EE134DFc08d379884eb8B4556b262`, verified on the testnet explorer; see `DEPLOY.md`.

## Description

Robinhood Chain gives every Stock Token a Chainlink price. Nothing on-chain says whether the underlying market is open, whether the stock is halted, whether a split changes the multiplier tomorrow, whether the issuer paused the oracle, or whether the NVDA address you were handed is a copycat. Chains run 24/7; the NYSE doesn't, and most tokenized-stock volume happens outside regular hours, when reference prices go stale and AMM pools drift. Robinhood's docs tell builders to check a Chainlink L2 Sequencer Uptime Feed before reading prices; Chainlink doesn't publish one for Robinhood Chain.

Stock-Hours Guard is an on-chain status registry plus a keeper. Any contract asks one question and gets Allow, Warn or Block with a 13-bit reason mask: unknown token, asset inactive, market closed, extended hours, trading halt, pending corporate action (ERC-8056 `effectiveAt()`), feed stale, feed invalid, price deviation, sequencer down, status stale, closing-only, oracle paused. Hard blocks and warnings are separated so a lending market can refuse a liquidation on a stale weekend price while an AMM only warns.

The sequencer signal the docs assume exists is built in: a sentinel quorum. Independent sentinels post heartbeats; `SEQUENCER_DOWN` is raised while at least `quorum` are silent or inside post-recovery grace, so one dead or malicious sentinel can't fake or hide an outage. Live as 2-of-3 across three providers (Railway, macOS, Android/Termux) with one real outage-and-recovery cycle in the on-chain history. The keeper has written every NYSE session transition on-chain since Sept 25.

Integrations: `GuardedV3Router` (Uniswap V3 SwapRouter interface, live on Robinhood Chain mainnet; deployed on testnet against a mock router with the same interface) and a Uniswap v4 `beforeSwap` hook. Example `GuardedVault`. 22 Foundry tests.

## Against the judging criteria

- **Functionality and code quality:** deployed and verified on testnet; keeper and three sentinels running since late September; 22 Foundry tests; every status change is a public on-chain event.
- **Impact and market:** every protocol that lists Stock Tokens on Robinhood Chain carries this risk: lending markets (liquidation on stale prices), DEXs and aggregators (routing into halted or rebasing tokens), vaults. Tokenized stocks on-chain passed $1B in 2026 and most volume is off-hours. The guard is one view call, so adoption cost is a few lines.
- **Novelty:** no on-chain market-status registry exists for tokenized stocks; halts, sessions, corporate actions and oracle pauses are each read from a different place today, and the sequencer-uptime gap on Robinhood Chain had no answer at all.
- **UX for downstream users:** one call, one verdict, reasons as bits; HTTP mirror for off-chain bots; Telegram alerts.
- **Open source and composability:** MIT. Reads Chainlink, ERC-8056 and the issuer's `oraclePaused()` directly; wraps the Uniswap V3 router and plugs into v4 as a hook; any contract can call `check()`.
- **Viability:** the paying customers are the protocols carrying liquidation and routing risk. M1 mainnet with the full roster and external sentinel operators (3-of-5); M2 L1 sentinel through the delayed inbox so the flag flips during an outage, plus the v4 hook on the first Stock-Token pool; M3 metered status API and signed attestations for bots, first lending-market integration.

## Known limitations

- Testnet has no Stock Tokens, equity feeds or Uniswap V3, so the testnet deployment uses mock tokens, feeds and a mock router with the exact mainnet interfaces. The Guard, router wrapper and hook bytecode are unchanged for mainnet. No mainnet deployment yet.
- All three sentinels are ours, on three separate providers. The quorum protects against one host failing, not against the operator.
- The keeper is a single writer; status freshness is enforced on-chain (`STATUS_STALE`), but a stopped keeper means stale status until it resumes.
- The NYSE calendar is maintained by hand for 2026–27.
- Zero external integrators so far.

## Prior entry

Built from Sept 22, 2026 inside the Arbitrum Open House Singapore window and submitted there on Oct 3 (Overall and Promising Products). Same codebase, further developed since (v2 sentinel quorum, V3 router wrapper, v4 hook, verified deployments).

## Team

Solo. Rav3n: GitHub Evoxravenlaude, X @rv3nlaud3, Telegram @rav3nlaud. Student.
