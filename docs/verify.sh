#!/usr/bin/env bash
# Explorer verification for StockGuard v2. Constructor args from DeployTestnet.s.sol:
# maxFeedAge=3600, maxStatusAge=900, corpActionWindow=86400, sequencerGrace=1800, sequencerUptimeFeed=0x0
set -e
cd "$(dirname "$0")/../contracts"
ARGS=$(cast abi-encode "constructor((uint32,uint32,uint32,uint32,address))" "(3600,900,86400,1800,0x0000000000000000000000000000000000000000)")
forge verify-contract 0x169197E31D3EE134DFc08d379884eb8B4556b262 src/StockGuard.sol:StockGuard \
  --verifier blockscout --verifier-url https://explorer.testnet.chain.robinhood.com/api \
  --chain-id 46630 --constructor-args "$ARGS" --watch
# GuardedVault takes (address guard)
forge verify-contract 0x4E02e6bAB5Eb5619a1e74174C3726852f12ac7af src/examples/GuardedVault.sol:GuardedVault \
  --verifier blockscout --verifier-url https://explorer.testnet.chain.robinhood.com/api \
  --chain-id 46630 --constructor-args $(cast abi-encode "constructor(address)" 0x169197E31D3EE134DFc08d379884eb8B4556b262) --watch

# Integrations (DeployIntegrations.s.sol). MockV3Router has no constructor args.
forge verify-contract 0x7C4ae0db1E1cB847FfA447A8d9957777F2A3EdDE src/mocks/MockV3Router.sol:MockV3Router \
  --verifier blockscout --verifier-url https://explorer.testnet.chain.robinhood.com/api \
  --chain-id 46630 --watch
# GuardedV3Router(guard, router, maxBps). Check maxBps against DeployIntegrations.s.sol before running.
forge verify-contract 0xdf0118474db9f1C4229F8Ef61E80c7Bca267F75B src/integrations/GuardedV3Router.sol:GuardedV3Router \
  --verifier blockscout --verifier-url https://explorer.testnet.chain.robinhood.com/api \
  --chain-id 46630 --constructor-args "$(cast abi-encode "constructor(address,address,uint256)" 0x169197E31D3EE134DFc08d379884eb8B4556b262 0x7C4ae0db1E1cB847FfA447A8d9957777F2A3EdDE 150)" --watch
