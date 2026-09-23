# Asset registry

`assets.<chainId>.json` — the list of genuine Robinhood Stock Tokens and their Chainlink feed proxies.
Build it from two official sources only, never from a ticker search on the explorer (copycat tokens exist):

- Token addresses: https://docs.robinhood.com/chain/contracts  (or `GET https://api.robinhood.com/rhj/assets` → `deployments[]`)
- Feed proxies:   https://docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood

Then: `cd keeper && npx tsx scripts/register.ts ../registry/assets.4663.json`
