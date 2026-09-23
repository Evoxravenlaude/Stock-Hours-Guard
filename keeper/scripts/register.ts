// Registers assets from a JSON file into StockGuard. Owner key required.
import { readFileSync } from "node:fs";
import { createWalletClient, createPublicClient, http, defineChain, parseAbi, type Address } from "viem";
import { privateKeyToAccount } from "viem/accounts";

const [file] = process.argv.slice(2);
if (!file) throw new Error("usage: tsx scripts/register.ts <assets.json>");
const rows = JSON.parse(readFileSync(file, "utf8")) as { symbol: string; token: Address; feed: Address }[];
const chain = defineChain({ id: Number(process.env.CHAIN_ID ?? 46630), name: "Robinhood Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 }, rpcUrls: { default: { http: [process.env.RPC_URL!] } } });
const account = privateKeyToAccount(process.env.KEEPER_PRIVATE_KEY as `0x${string}`);
const wallet = createWalletClient({ chain, account, transport: http() });
const pub = createPublicClient({ chain, transport: http() });
const abi = parseAbi(["function registerAsset(address token,string symbol,address feed)", "function registered(address) view returns (bool)"]);
const guard = process.env.GUARD_ADDRESS as Address;
for (const r of rows) {
  if (await pub.readContract({ address: guard, abi, functionName: "registered", args: [r.token] })) { console.log("skip", r.symbol); continue; }
  const hash = await wallet.writeContract({ address: guard, abi, functionName: "registerAsset", args: [r.token, r.symbol, r.feed] });
  console.log("registered", r.symbol, hash);
}
