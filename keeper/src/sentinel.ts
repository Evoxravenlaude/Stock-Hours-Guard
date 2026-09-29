/**
 * Standalone sentinel: posts heartbeat() on a fixed cadence and nothing else.
 * Give this to other builders on Robinhood Chain. Each sentinel needs its own key,
 * registered by the Guard owner with setSentinel(addr, true).
 *
 *   SENTINEL_PRIVATE_KEY=0x... GUARD_ADDRESS=0x... npm run sentinel
 */
import "dotenv/config";
import { createWalletClient, createPublicClient, http, defineChain, parseAbi, type Address } from "viem";
import { privateKeyToAccount } from "viem/accounts";

const RPC_URL = process.env.RPC_URL ?? "https://rpc.testnet.chain.robinhood.com";
const CHAIN_ID = Number(process.env.CHAIN_ID ?? 46630);
const GUARD = process.env.GUARD_ADDRESS as Address;
const EVERY = Number(process.env.HEARTBEAT_MS ?? 4 * 60 * 1000);
const key = process.env.SENTINEL_PRIVATE_KEY ?? process.env.KEEPER_PRIVATE_KEY;
if (!GUARD || !key) throw new Error("GUARD_ADDRESS and SENTINEL_PRIVATE_KEY required");

const chain = defineChain({ id: CHAIN_ID, name: "Robinhood Chain", nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } } });
const account = privateKeyToAccount(key as `0x${string}`);
const wallet = createWalletClient({ chain, account, transport: http(RPC_URL) });
const pub = createPublicClient({ chain, transport: http(RPC_URL) });
const abi = parseAbi(["function heartbeat()", "function isSentinel(address) view returns (bool)",
  "function sentinelState() view returns (uint256 silent, uint256 recovering)", "function quorum() view returns (uint8)"]);

async function beat() {
  try {
    const ok = await pub.readContract({ address: GUARD, abi, functionName: "isSentinel", args: [account.address] });
    if (!ok) { console.error(`${account.address} is not a registered sentinel`); return; }
    const h = await wallet.writeContract({ address: GUARD, abi, functionName: "heartbeat" });
    const [silent, recovering] = await pub.readContract({ address: GUARD, abi, functionName: "sentinelState" });
    const q = await pub.readContract({ address: GUARD, abi, functionName: "quorum" });
    console.log(`[${new Date().toISOString()}] beat ${h} | silent=${silent} recovering=${recovering} quorum=${q}`);
  } catch (e) { console.error("beat failed:", (e as Error).message); }
}
beat(); setInterval(beat, EVERY);
