# Testnet deploy — Robinhood Chain Testnet (chain 46630)

Testnet has WETH but **no Stock Tokens and no Chainlink equity feeds**, so the testnet
deployment uses mock tokens/feeds with the exact mainnet interfaces. The Guard contract is
byte-identical to what mainnet gets.

## 0. Prereqs
- Foundry installed (`curl -L https://foundry.paradigm.xyz | bash && foundryup`)
- A fresh deployer wallet. Export its key: `export PK=0x...`
- Testnet ETH: https://faucet.testnet.chain.robinhood.com (or Alchemy's Robinhood Testnet faucet, 0.1 ETH/day, needs a little mainnet history on the address)
- `export RPC=https://rpc.testnet.chain.robinhood.com`

## 1. Deploy
```bash
cd contracts && forge install && forge test
forge script script/DeployTestnet.s.sol --rpc-url $RPC --broadcast --private-key $PK -vv
```
Copy the printed addresses (StockGuard, GuardedVault, 3 tokens, 3 feeds) into `keeper/.env`
and into `registry/assets.46630.json`.

## 2. Verify on the explorer (Blockscout)
```bash
forge verify-contract <GUARD_ADDR> src/StockGuard.sol:StockGuard \
  --verifier blockscout --verifier-url https://explorer.testnet.chain.robinhood.com/api \
  --chain-id 46630 --constructor-args $(cast abi-encode "constructor((uint32,uint32,uint32,uint32,address))" "(3600,900,86400,1800,0x0000000000000000000000000000000000000000)")
```

## 3. Run the keeper
```bash
cd ../keeper && npm i && cp .env.example .env   # set GUARD_ADDRESS, KEEPER_PRIVATE_KEY (= PK for now)
npm run dev
curl "localhost:8787/check/<NVDA_TOKEN>?price=18000000000&maxBps=150"
```
The keeper reads live halt/tradability from Robinhood's mainnet REST API by symbol, so the
testnet mocks get real market state.

## 4. Drive the demo scenarios
```bash
export GUARD=<addr> TOKEN=<nvda token> FEED=<nvda feed>
for s in regular closed halt stale split paused; do
  SCENARIO=$s forge script script/Demo.s.sol --rpc-url $RPC --broadcast --private-key $PK
done
```
Each run prints the verdict and reason bits; `curl localhost:8787/check/$TOKEN` shows the same
answer decoded.

## 5. Prove the Arbitrum "new work" claim
Commit and push after step 1 with the deploy tx hash and addresses in this file.

## Testnet Deployment (Robinhood Chain testnet, chain 46630)

- StockGuard:   0x0bb080330b8a361fb0cdd32432d770c1ebea86bc
- GuardedVault: 0x14c2805250cd7ebe46241d06536fd3243b47e268
- NVDA token:   0x19d42ac5f71e4753610d225749fd7379f57b3017
- NVDA feed:    0x3fca4642e963b6f829aab21213af1066a174915c
- AAPL token:   0x712330290e6f7e3a8516c11b9b54545ebe5ee2d9
- AAPL feed:    0x507bd185b134d0feced54a6a045fafc6388cccd2
- TSLA token:   0x6f765e81a7414008895e61d8999877ca2ef094b7
- TSLA feed:    0x1a284b05b67f46c054e175a2c94bfe448aca6782

Deployment tx: 0x8aeb6937c68f0da1a5fd0b85ae1d54b8c8ff318a1cce470b4ec69d6a8ab33009

## 6. Sentinel quorum (after upgrading the contract)
The quorum version of StockGuard is a new deployment (storage layout changed). Redeploy with
`DeployTestnet.s.sol`, update `GUARD_ADDRESS` on Railway, then:
```bash
cast send $GUARD "setSentinel(address,bool)" <sentinel2> true --rpc-url $RPC --private-key $PK
cast send $GUARD "setSentinel(address,bool)" <sentinel3> true --rpc-url $RPC --private-key $PK
cast send $GUARD "setQuorum(uint8,uint32)" 2 900 --rpc-url $RPC --private-key $PK
cast call $GUARD "sentinelState()(uint256,uint256)" --rpc-url $RPC
```
Run `npm run sentinel` on each extra machine with its own `SENTINEL_PRIVATE_KEY` (a second Railway
service works). Two sentinels on different hosts plus the keeper gives a 2-of-3 quorum.

## v2 Deployment (sentinel quorum)

Deployed 2026-10-01. Fresh deployment, not an upgrade — storage layout changed.

| Contract | Address |
|---|---|
| StockGuard | 0x169197E31D3EE134DFc08d379884eb8B4556b262 |
| GuardedVault | 0x4E02e6bAB5Eb5619a1e74174C3726852f12ac7af |
| NVDA token / feed | 0xcc2e5173B4b7A025536991be893AE5945A3ba144 / 0xe615619ff4af78488cA0077Aa2E0Df208aEc47F5 |
| AAPL token / feed | 0x5166775298cbC46c8243f4Edd65E63D50d8CbF1a / 0xF33057f22974d0efA20EBC16Fb6998278661567a |
| TSLA token / feed | 0xb798193702C4e27Add00c0373fEbaA3BB7845821 / 0x11d47BB1e69d332C167d294C4D8C16E09C19fA10 |

Deploy tx: 0x4563cda4dcc03a0e70a3e52d7ba50276e1abdab6d216219a60aeda480fafaf3e

### Sentinel quorum: 2-of-3, three independent hosts

| Sentinel | Address | Host |
|---|---|---|
| 1 (keeper) | 0x0D8FafA10024A45B0Edb86bA5cB716A9DF997036 | Railway |
| 2 | 0xA91292A59416cDD46B83850748307c4B18180899 | Mac (pm2 + launchd) |
| 3 | 0x16aD8a1550D2b027cC1A235AADd07aab355a0393 | Android/Termux (tmux + wake-lock) |

`setQuorum(2, 900)` — 2 of 3 sentinels must be unhealthy to raise `SEQUENCER_DOWN`, outage threshold 900s.

Wired 2026-10-01. Confirmed live via `sentinelState()`; recorded one real outage/recovery cycle during setup (Termux sentinel killed by Android/MIUI background management, recovered after battery/autostart exclusions applied) — see commit history and session logs for the timestamped sequence.
