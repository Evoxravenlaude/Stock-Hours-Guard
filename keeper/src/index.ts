import "dotenv/config";
import { createPublicClient, createWalletClient, http, defineChain, parseAbi, type Address } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { Hono } from "hono";
import { serve } from "@hono/node-server";
import { sessionAt, sessionName, type SessionValue } from "./session.js";

// ---------------------------------------------------------------- config
const env = (k: string, d?: string) => process.env[k] ?? d ?? (() => { throw new Error(`missing env ${k}`); })();
const RPC_URL = env("RPC_URL", "https://rpc.testnet.chain.robinhood.com");
const CHAIN_ID = Number(env("CHAIN_ID", "46630"));
const GUARD = env("GUARD_ADDRESS") as Address;
const POLL_MS = Number(env("POLL_MS", "30000"));
const PORT = Number(env("PORT", "8787"));
const DRY_RUN = !process.env.KEEPER_PRIVATE_KEY;

const chain = defineChain({
  id: CHAIN_ID,
  name: CHAIN_ID === 4663 ? "Robinhood Chain" : "Robinhood Chain Testnet",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
});

const guardAbi = parseAbi([
  "function tokens() view returns (address[])",
  "function status(address) view returns ((string symbol,uint8 session,bool halted,bool active,uint8 tradability,uint64 updatedAt))",
  "function check(address token,uint256 quotedPrice,uint256 maxDeviationBps) view returns (uint8 verdict,uint256 reasons)",
  "function updateStatusBatch(address[] tokenList,uint8[] sessions,bool[] halted,bool[] active,uint8[] tradability)",
  "function heartbeat()",
]);

const pub = createPublicClient({ chain, transport: http(RPC_URL) });
const wallet = DRY_RUN ? null : createWalletClient({
  chain, transport: http(RPC_URL), account: privateKeyToAccount(process.env.KEEPER_PRIVATE_KEY as `0x${string}`),
});

// ---------------------------------------------------------------- Robinhood REST
const RH = "https://api.robinhood.com/rhj";
type RhAsset = {
  tokenSymbol: string; status: string;
  deployments: { contractAddress: string; chainId: number }[];
  currentMultiplier: string; pendingMultiplier: string; pendingMultiplierEffectiveTime?: string;
  tradingCapabilities?: { fractionalTradability: string | null; allDayTradability: string | null } | null;
};
type RhQuote = { tokenSymbol: string; bid: string; ask: string; isTradingHalt: boolean; generatedAt: string };

async function getJson<T>(url: string): Promise<T> {
  const r = await fetch(url, { headers: { accept: "application/json" } });
  if (!r.ok) throw new Error(`${url} -> ${r.status}`);
  return r.json() as Promise<T>;
}

// Tradability enum order in contract: Unknown=0, Tradable=1, Untradable=2, ClosingOnly=3, OpeningOnly=4
function tradabilityCode(a: RhAsset): number {
  const t = a.tradingCapabilities?.allDayTradability ?? a.tradingCapabilities?.fractionalTradability ?? null;
  switch (t) {
    case "tradable": return 1;
    case "untradable": return 2;
    case "position_closing_only": return 3;
    case "position_opening_only": return 4;
    default: return 0;
  }
}

// ---------------------------------------------------------------- state
type Snapshot = {
  token: Address; symbol: string; session: SessionValue; sessionName: string; halted: boolean; active: boolean;
  tradability: number; bid?: string; ask?: string; pendingMultiplier?: string; pendingEffective?: string; at: string;
};
const latest = new Map<string, Snapshot>();
const HEARTBEAT_INTERVAL_MS = 5 * 60 * 1000; // well under the contract's 10-minute outage window
let lastOnchainWrite = 0;
const REASONS = ["UNKNOWN_TOKEN","ASSET_INACTIVE","MARKET_CLOSED","EXTENDED_HOURS","TRADING_HALT","PENDING_CORP_ACT",
  "FEED_STALE","FEED_INVALID","PRICE_DEVIATION","SEQUENCER_DOWN","STATUS_STALE","CLOSING_ONLY"];
export const decodeReasons = (bits: bigint) => REASONS.filter((_, i) => (bits >> BigInt(i)) & 1n);

async function tick() {
  const tokens = (await pub.readContract({ address: GUARD, abi: guardAbi, functionName: "tokens" })) as Address[];
  if (tokens.length === 0) { console.log("no registered tokens yet"); return; }

  const { assets } = await getJson<{ assets: RhAsset[] }>(`${RH}/assets`);
  const byAddr = new Map<string, RhAsset>();
  for (const a of assets) for (const d of a.deployments) byAddr.set(d.contractAddress.toLowerCase(), a);

  const session = sessionAt();
  const rows: Snapshot[] = [];
  for (const t of tokens) {
    const a = byAddr.get(t.toLowerCase());
    // On testnet the REST roster only lists mainnet deployments; fall back to on-chain symbol.
    const symbol = a?.tokenSymbol ?? (await pub.readContract({ address: GUARD, abi: guardAbi, functionName: "status", args: [t] }) as any).symbol;
    const mainnetAsset = a ?? assets.find((x) => x.tokenSymbol === symbol);
    let halted = false, bid: string | undefined, ask: string | undefined;
    try {
      const q = await getJson<{ quotes: RhQuote[] }>(`${RH}/prices/${symbol}`);
      const quote = q.quotes?.[0];
      if (quote) { halted = quote.isTradingHalt; bid = quote.bid; ask = quote.ask; }
    } catch (e) { console.warn(`price ${symbol}:`, (e as Error).message); }

    rows.push({
      token: t, symbol, session, sessionName: sessionName(session), halted,
      active: mainnetAsset ? mainnetAsset.status === "ASSET_STATUS_ACTIVE" : true,
      tradability: mainnetAsset ? tradabilityCode(mainnetAsset) : 0,
      bid, ask,
      pendingMultiplier: mainnetAsset?.pendingMultiplier || undefined,
      pendingEffective: mainnetAsset?.pendingMultiplierEffectiveTime,
      at: new Date().toISOString(),
    });
  }

  // only write when something a contract cares about changed
  const changed = rows.filter((r) => {
    const p = latest.get(r.token.toLowerCase());
    return !p || p.session !== r.session || p.halted !== r.halted || p.active !== r.active || p.tradability !== r.tradability;
  });
  for (const r of rows) latest.set(r.token.toLowerCase(), r);

  if (changed.length === 0) {
    console.log(`[${new Date().toISOString()}] ${sessionName(session)} — no change`);
    if (!DRY_RUN && wallet && Date.now() - lastOnchainWrite > HEARTBEAT_INTERVAL_MS) {
      const hbHash = await wallet.writeContract({ address: GUARD, abi: guardAbi, functionName: "heartbeat", args: [] });
      lastOnchainWrite = Date.now();
      console.log("heartbeat tx", hbHash);
    }
    return;
  }
  console.log(`[${new Date().toISOString()}] ${changed.length} change(s):`, changed.map((c) => `${c.symbol}:${c.sessionName}${c.halted ? ":HALT" : ""}`).join(" "));
  await notify(changed);

  if (DRY_RUN || !wallet) { console.log("DRY_RUN: not writing on-chain"); return; }
  const hash = await wallet.writeContract({
    address: GUARD, abi: guardAbi, functionName: "updateStatusBatch",
    args: [changed.map((c) => c.token), changed.map((c) => c.session), changed.map((c) => c.halted),
           changed.map((c) => c.active), changed.map((c) => c.tradability)],
  });
  lastOnchainWrite = Date.now();
  console.log("tx", hash);
}

async function notify(changed: Snapshot[]) {
  const tok = process.env.TELEGRAM_BOT_TOKEN, chat = process.env.TELEGRAM_CHAT_ID;
  if (!tok || !chat) return;
  const text = changed.map((c) => `${c.halted ? "🛑" : "•"} ${c.symbol}: ${c.sessionName}${c.halted ? " (HALTED)" : ""}${c.active ? "" : " (INACTIVE)"}`).join("\n");
  await fetch(`https://api.telegram.org/bot${tok}/sendMessage`, {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ chat_id: chat, text }),
  }).catch(() => {});
}

// ---------------------------------------------------------------- HTTP API (mirrors the on-chain answer)
const app = new Hono();
app.get("/", (c) => c.json({ ok: true, guard: GUARD, chainId: CHAIN_ID, session: sessionName(sessionAt()) }));
app.get("/status", (c) => c.json([...latest.values()]));
app.get("/status/:token", (c) => {
  const s = latest.get(c.req.param("token").toLowerCase());
  return s ? c.json(s) : c.json({ error: "unknown token" }, 404);
});
app.get("/check/:token", async (c) => {
  const token = c.req.param("token") as Address;
  const quoted = BigInt(c.req.query("price") ?? "0");
  const bps = BigInt(c.req.query("maxBps") ?? "0");
  const [verdict, reasons] = (await pub.readContract({ address: GUARD, abi: guardAbi, functionName: "check", args: [token, quoted, bps] })) as [number, bigint];
  return c.json({ token, verdict: ["Allow", "Warn", "Block"][verdict], reasons: decodeReasons(reasons), bits: reasons.toString() });
});

serve({ fetch: app.fetch, port: PORT }, () => console.log(`keeper api on :${PORT} (${DRY_RUN ? "dry-run" : "live"})`));
const loop = async () => { try { await tick(); } catch (e) { console.error("tick failed:", (e as Error).message); } };
loop(); setInterval(loop, POLL_MS);
