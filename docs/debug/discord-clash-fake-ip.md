---
summary: Discord WS silent failure under Clash Fake IP — async registerClient race + proxy agent
read_when:
  - Discord shows connected but bot never replies
  - Gateway stuck at "awaiting gateway readiness" with no timeout or 1006 error
  - Running behind Clash TUN/Fake IP mode
title: "Discord Gateway Silent Failure under Clash Fake IP"
---

# Discord Gateway Silent Failure under Clash Fake IP

## Symptoms

- `channels status` shows `connected: false`, `lastEventAt: null`
- Log shows: `discord client initialized; awaiting gateway readiness` then nothing, or 1006 closes
- After 15s: `WebSocket connection closed with code 1006` → `Attempting resume with backoff`
- All inbound messages fail: `Cannot find module './route-reply.runtime-XXX.js'` (if dist is stale)

---

## Root Cause 1 (Primary): async registerClient Race Condition

**This is the deeper bug.** Carbon's `Client` constructor calls `plugin.registerClient?.(this)` **without
`await`** (`@buape/carbon/dist/src/classes/Client.js:122`). But `SafeGatewayPlugin.registerClient()`
is `async` — it first fetches `/gateway/bot` (up to 10s timeout) before calling `super.registerClient()`
which actually triggers `connect()` and creates the WebSocket.

Timeline without fix:

```
T+0s   Carbon constructor fires registerClient() (not awaited)
T+0s   waitForDiscordGatewayReady() starts 15s polling (isConnected=false)
T+10s  HTTP fetch completes → super.registerClient() → connect() → WebSocket created
T+15s  Lifecycle timeout → gateway.disconnect() interrupts mid-handshake → code 1006
```

**Fix**: Pre-fetch gateway info in `provider.ts` _before_ `new Client(...)`, then pass it as
`prefetchedGatewayInfo` to `createDiscordGatewayPlugin()`. The plugin constructor injects it into
`this.gatewayInfo` so `registerClient()` skips the async fetch entirely — WebSocket starts at T+0s.

```typescript
// provider.ts — BEFORE new Client(...)
const prefetchedGatewayInfo = await fetchDiscordGatewayInfoWithTimeout({
  token,
  fetchImpl,
  fetchInit,
})
  .then((info) => ({ info, usedFallback: false }))
  .catch((error) => resolveGatewayInfoWithFallback({ runtime, error }));

const clientPlugins = [
  createDiscordGatewayPlugin({
    discordConfig: discordCfg,
    runtime,
    prefetchedGatewayInfo: prefetchedGatewayInfo.info, // <-- key
  }),
];
```

---

## Root Cause 2 (Secondary): Clash Fake IP routing for unmatched processes

Clash's PROCESS-NAME rules may match `node` but not `openclaw-gateway`. In Fake IP mode, unmatched
processes get fake IPs (`198.18.x.x`) — TCP handshake completes but no data flows.

**Fix**: Set `channels.discord.proxy = "http://127.0.0.1:7897"` in config so the gateway explicitly
routes through Clash's mixed port instead of going through Fake IP system routing.

---

## Proxy Agent: HttpsProxyAgent (not SocksProxyAgent)

Use `HttpsProxyAgent` for the WebSocket connection. It uses HTTP CONNECT tunneling — the correct
method for WebSocket proxy. Clash's mixed port 7897 supports both HTTP and SOCKS5; HTTP CONNECT works
fine here.

**SocksProxyAgent was tried previously and caused worse failures**: the SOCKS5 negotiation compounds
the async race (Root Cause 1) — if `gateway.disconnect()` fires mid-SOCKS5 handshake, the TCP
connection is left in a zombie state and the process hangs waiting for a socket that never closes.

```typescript
// gateway-plugin.ts — correct
import { HttpsProxyAgent } from "https-proxy-agent";
const wsAgent = new HttpsProxyAgent<string>(proxy); // proxy = "http://127.0.0.1:7897"
```

---

## Stale dist/ Issue

If the gateway process is running while `pnpm build` regenerates chunk files with new hashes,
every inbound message fails with `Cannot find module './route-reply.runtime-XXX.js'`. The process
must be restarted after each build. The macOS app manages this automatically; if running via CLI,
kill the old process before restarting.

---

## Fix Summary (2026-04-05)

1. `provider.ts`: Pre-fetch gateway info before `new Client(...)`, pass as `prefetchedGatewayInfo`
2. `gateway-plugin.ts`: Accept `prefetchedGatewayInfo`, inject into `this.gatewayInfo` in constructor
3. `gateway-plugin.ts`: Revert `SocksProxyAgent` → `HttpsProxyAgent`
4. `extensions/discord/package.json`: Remove `socks-proxy-agent` dependency
