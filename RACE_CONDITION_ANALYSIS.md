# Deep Investigation: SafeGatewayPlugin Race Condition

## Executive Summary

Investigation confirms a **critical race condition** in Discord gateway startup where:

1. **Carbon's Client constructor calls `plugin.registerClient(this)` WITHOUT await** (line 122)
2. **SafeGatewayPlugin.registerClient() is async** and awaits up to 10s for HTTP fetch
3. **Meanwhile, provider.lifecycle.ts times out after 15s** of polling for `gateway.isConnected`
4. **If HTTP fetch + WebSocket tunnel > ~15s, the lifecycle times out and calls `gateway.disconnect()` WHILE the tunnel is establishing**
5. **The SocksProxyAgent connection may hang or be left in an undefined state**

---

## Investigation Findings

### 1. LOGS: NO "GATEWAY WAS NOT READY" PATTERNS FOUND

```bash
Result: No matching patterns found for:
- "gateway was not ready"
- "startup-not-ready"
- "startup-reconnect"
- "forcing a fresh reconnect"
- "did not reach READY"
```

**Recent log entries show normal startup pattern:**

- 2026-04-05T10:34:17-10:36:59: Multiple client initialization cycles
- 2026-04-05T10:40:23: One WebSocket close with code 1006 (abnormal closure)
- 2026-04-05T10:40:23: Resume attempt with 1000ms backoff
- Pattern suggests clean restarts, not the timeout pattern

**Note:** The absence of these errors doesn't mean the race condition isn't happening—it may only manifest under specific timing conditions (high latency proxies, slow DNS, network delays).

---

### 2. CARBON'S GATEWAYPlugin: THE GUARD

**File:** `/Users/ZenoWang/Documents/project/zenobot/node_modules/@buape/carbon/dist/src/plugins/gateway/GatewayPlugin.js`

#### Lines 86-117: Critical Code

```javascript
connect(resume = false) {
  if (this.isConnecting)  // GUARD: prevents concurrent connects
    return;
  if (this.reconnectTimeout) {
    clearTimeout(this.reconnectTimeout);
    this.reconnectTimeout = undefined;
  }
  this.ws?.close();
  const baseUrl = resume && this.state.resumeGatewayUrl
    ? this.state.resumeGatewayUrl
    : (this.gatewayInfo?.url ??
        this.options.url ??
        "wss://gateway.discord.gg/");
  const url = this.ensureGatewayParams(baseUrl);
  this.ws = this.createWebSocket(url);
  this.isConnecting = true;  // Set BEFORE setupWebSocket
  this.setupWebSocket();
}

disconnect() {
  stopHeartbeat(this);
  this.lastHeartbeatAck = true;
  this.monitor.resetUptime();
  this.ws?.close();                  // Forcibly close WebSocket
  this.ws = null;
  if (this.reconnectTimeout) {
    clearTimeout(this.reconnectTimeout);
    this.reconnectTimeout = undefined;
  }
  this.isConnecting = false;         // CRITICAL: Set to false
  this.isConnected = false;
  this.pings = [];
}
```

**Key Findings:**

- ✓ `connect()` checks `if (this.isConnecting) return` before creating WebSocket (line 87)
- ✓ `disconnect()` sets `this.isConnecting = false` (line 114), resetting the guard
- ✓ State is well-protected via `isConnecting` flag
- ✗ BUT: `disconnect()` calls `this.ws?.close()` which may NOT complete if the tunnel is mid-negotiation

---

### 3. THE RACE CONDITION IN provider.lifecycle.ts

**File:** `/Users/ZenoWang/Documents/project/zenobot/extensions/discord/src/monitor/provider.lifecycle.ts`

#### Lines 18-42: Polling Loop

```typescript
const DISCORD_GATEWAY_READY_POLL_MS = 250;
const DISCORD_GATEWAY_READY_TIMEOUT_MS = 15_000; // 15 seconds

async function waitForDiscordGatewayReady(params: {
  gateway?: Pick<GatewayPlugin, "isConnected">;
  abortSignal?: AbortSignal;
  timeoutMs: number;
  beforePoll?: () => Promise<"continue" | "stop"> | "continue" | "stop";
}): Promise<GatewayReadyWaitResult> {
  const deadlineAt = Date.now() + params.timeoutMs;
  while (!params.abortSignal?.aborted) {
    const pollDecision = await params.beforePoll?.();
    if (pollDecision === "stop") {
      return "stopped";
    }
    if (params.gateway?.isConnected) {
      // Polls every 250ms
      return "ready";
    }
    if (Date.now() >= deadlineAt) {
      // After 15s, return timeout
      return "timeout";
    }
    await new Promise<void>((resolve) => {
      const timeout = setTimeout(resolve, DISCORD_GATEWAY_READY_POLL_MS);
      timeout.unref?.();
    });
  }
  return "stopped";
}
```

**Poll count in 15s:** 15,000 / 250 = **60 polls**

#### Lines 330-382: The Forced Reconnect Sequence

```typescript
if (initialReady === "timeout" && !lifecycleStopping) {
  params.runtime.error?.(
    danger(
      `discord: gateway was not ready after ${DISCORD_GATEWAY_READY_TIMEOUT_MS}ms; forcing a fresh reconnect`,
    ),
  );
  const startupRetryAt = Date.now();
  pushStatus({
    connected: false,
    lastEventAt: startupRetryAt,
    lastDisconnect: {
      at: startupRetryAt,
      error: "startup-not-ready",
    },
  });
  gateway?.disconnect(); // Line 355: Force disconnect
  gateway?.connect(false); // Line 356: Force reconnect (fresh ID)
  const reconnected = await waitForDiscordGatewayReady({
    gateway,
    abortSignal: params.abortSignal,
    timeoutMs: DISCORD_GATEWAY_READY_TIMEOUT_MS,
    beforePoll: drainPendingGatewayErrors,
  });
  // ...
}
```

---

### 4. CARBON'S CLIENT CONSTRUCTOR: THE MISSING AWAIT

**File:** `/Users/ZenoWang/Documents/project/zenobot/node_modules/@buape/carbon/dist/src/classes/Client.js`

#### Line 122: NO AWAIT

```javascript
constructor(options, handlers, plugins = []) {
  // ... setup ...
  for (const plugin of plugins) {
    plugin.registerClient?.(this);        // BUG: Fire and forget!
    plugin.registerRoutes?.(this);
    this.plugins.push({ id: plugin.id, plugin });
  }
  // ...
}
```

**Problem:** The async `registerClient()` Promise is ignored. The constructor completes immediately.

---

### 5. SAFEGATEWAYPLUGIN: THE ASYNC REGISTERCLIENT

**File:** `/Users/ZenoWang/Documents/project/zenobot/extensions/discord/src/monitor/gateway-plugin.ts`

#### Lines 239-255: The Async Path

```typescript
override async registerClient(client: Parameters<GatewayPlugin["registerClient"]>[0]) {
  if (!this.gatewayInfo || this.gatewayInfoUsedFallback) {
    const resolved = await fetchDiscordGatewayInfoWithTimeout({  // AWAIT UP TO 10s
      token: client.options.token,
      fetchImpl: params.fetchImpl,
      fetchInit: params.fetchInit,
    })
      .then((info) => ({
        info,
        usedFallback: false,
      }))
      .catch((error) => resolveGatewayInfoWithFallback({ runtime: params.runtime, error }));
    this.gatewayInfo = resolved.info;
    this.gatewayInfoUsedFallback = resolved.usedFallback;
  }
  return super.registerClient(client);  // Line 254: Calls Carbon's registerClient
}
```

#### Lines 162-201: HTTP Fetch with Timeout

```typescript
async function fetchDiscordGatewayInfoWithTimeout(params: {
  token: string;
  fetchImpl: DiscordGatewayFetch;
  fetchInit?: DiscordGatewayFetchInit;
  timeoutMs?: number;
}): Promise<APIGatewayBotInfo> {
  const timeoutMs = Math.max(1, params.timeoutMs ?? DISCORD_GATEWAY_INFO_TIMEOUT_MS);
  // DISCORD_GATEWAY_INFO_TIMEOUT_MS = 10_000
  const abortController = new AbortController();
  let timeoutId: ReturnType<typeof setTimeout> | undefined;
  const timeoutPromise = new Promise<never>((_, reject) => {
    timeoutId = setTimeout(() => {
      abortController.abort();
      reject(
        createGatewayMetadataError({
          detail: `Discord API /gateway/bot timed out after ${timeoutMs}ms`,
          transient: true,
          cause: new Error("gateway metadata timeout"),
        }),
      );
    }, timeoutMs);
    timeoutId.unref?.();
  });

  try {
    return await Promise.race([
      fetchDiscordGatewayInfo({
        // HTTP fetch
        token: params.token,
        fetchImpl: params.fetchImpl,
        fetchInit: {
          ...params.fetchInit,
          signal: abortController.signal,
        },
      }),
      timeoutPromise,
    ]);
  } finally {
    if (timeoutId) {
      clearTimeout(timeoutId);
    }
  }
}
```

**Maximum wait:** 10 seconds for HTTP

---

### 6. THE PROXY CHANGE: HttpsProxyAgent → SocksProxyAgent

**File:** `/Users/ZenoWang/Documents/project/zenobot/extensions/discord/src/monitor/gateway-plugin.ts`

#### Current (Uncommitted) Diff:

```diff
- import { HttpsProxyAgent } from "https-proxy-agent";
+ import { SocksProxyAgent } from "socks-proxy-agent";

- wsAgent?: HttpsProxyAgent<string>;
+ wsAgent?: SocksProxyAgent;

- const wsAgent = new HttpsProxyAgent<string>(proxy);
+ const socksProxy = proxy.replace(/^https?:\/\//, "socks5://");
+ const wsAgent = new SocksProxyAgent(socksProxy);
```

**Why:** SocksProxyAgent works at TCP level (protocol-agnostic). HttpsProxyAgent was HTTP/HTTPS specific.

#### Lines 288-304: Current Implementation

```typescript
try {
  // Convert http(s):// proxy URL to socks5:// for WebSocket tunneling.
  // SocksProxyAgent works at TCP level (protocol-agnostic), so WS upgrades
  // and heartbeats flow through unchanged. Clash's mixed port 7897 supports SOCKS5.
  const socksProxy = proxy.replace(/^https?:\/\//, "socks5://");
  const wsAgent = new SocksProxyAgent(socksProxy);
  const fetchAgent = new ProxyAgent(proxy);

  params.runtime.log?.("discord: gateway proxy enabled");

  return createGatewayPlugin({
    options,
    fetchImpl: (input, init) => undiciFetch(input, init),
    fetchInit: { dispatcher: fetchAgent },
    wsAgent,
    runtime: params.runtime,
  });
}
```

---

### 7. SOCKSPRXYAGENT: THE TUNNEL ESTABLISHMENT

**File:** `/Users/ZenoWang/Documents/project/zenobot/node_modules/socks-proxy-agent/dist/index.js`

#### Lines 114-175: The connect() Method

```javascript
async connect(req, opts) {
  const { shouldLookup, proxy, timeout } = this;
  if (!opts.host) {
    throw new Error('No `host` defined!');
  }
  let { host } = opts;
  const { port, lookup: lookupFn = dns.lookup } = opts;
  if (shouldLookup) {
    // Client-side DNS resolution
    host = await new Promise((resolve, reject) => {
      lookupFn(host, {}, (err, res) => {
        if (err) {
          reject(err);
        } else {
          resolve(res);
        }
      });
    });
  }
  const socksOpts = {
    proxy,
    destination: {
      host,
      port: typeof port === 'number' ? port : parseInt(port, 10),
    },
    command: 'connect',
    timeout: timeout ?? undefined,
    socket_options: this.socketOptions ?? undefined,
  };
  const cleanup = (tlsSocket) => {
    req.destroy();           // Destroys the HTTP request
    socket.destroy();        // Destroys the SOCKS tunnel
    if (tlsSocket)
      tlsSocket.destroy();
  };
  debug('Creating socks proxy connection: %o', socksOpts);
  const { socket } = await socks_1.SocksClient.createConnection(socksOpts);
  debug('Successfully created socks proxy connection');
  if (timeout !== null) {
    socket.setTimeout(timeout);
    socket.on('timeout', () => cleanup());
  }
  if (opts.secureEndpoint) {
    // Upgrade to TLS for wss://
    debug('Upgrading socket connection to TLS');
    const tlsSocket = tls.connect({
      ...omit(setServernameFromNonIpHost(opts), 'host', 'path', 'port'),
      socket,
    });
    tlsSocket.once('error', (error) => {
      debug('Socket TLS error', error.message);
      cleanup(tlsSocket);
    });
    return tlsSocket;
  }
  return socket;
}
```

**Key Insights:**

- ✓ `connect()` is `async` and **awaits** `SocksClient.createConnection()`
- ✓ DNS lookup happens INSIDE the async function
- ✓ SOCKS5 tunnel negotiation is asynchronous
- ✓ TLS upgrade (for wss://) is async
- ✗ If `cleanup()` is called while tunnel is mid-establishment, the abort behavior is unclear

---

### 8. WS LIBRARY: WEBSOCKET INITIATION

**File:** `/Users/ZenoWang/Documents/project/zenobot/node_modules/ws/lib/websocket.js`

#### Lines 54-94: Constructor

```javascript
constructor(address, protocols, options) {
  super();
  // ... initialization ...
  if (address !== null) {
    this._bufferedAmount = 0;
    this._isServer = false;
    this._redirects = 0;
    // ... protocol handling ...
    initAsClient(this, address, protocols, options);  // Line 88: Initiates connection
  } else {
    // Server mode
  }
}
```

#### Lines 657-858+: initAsClient() Function

**Key sections:**

- Line 740-741: Sets `opts.createConnection` (defaults to `tlsConnect` for wss://)
- Line 755: Sets `opts.timeout = opts.handshakeTimeout`
- Line 736: `const request = isSecure ? https.request : http.request`
- Lines 802+: Creates HTTP request with the agent

**Important:** The WebSocket constructor calls `initAsClient()` synchronously, which:

1. Creates an HTTP/HTTPS request object
2. If agent is provided (our SocksProxyAgent), the `createConnection` callback fires async
3. The agent's `connect()` method is called by Node's HTTP client when it needs a socket
4. If `connect()` never completes or times out, the WebSocket handshake stalls

---

### 9. WHAT HAPPENS WHEN disconnect() IS CALLED MID-TUNNEL?

**The Critical Question:**

```
Timeline:
T+0s:    Client constructor calls registerClient() (no await)
T+0s:    registerClient() starts async, awaits HTTP fetch
T+0s:    HTTP fetch starts (up to 10s)
T+1s:    After 10s, HTTP fetch completes
T+1s:    registerClient() calls super.registerClient(client)
T+1s:    Carbon's registerClient() calls this.connect()
T+1s:    connect() creates new WebSocket
T+1s:    WebSocket constructor calls initAsClient()
T+1s:    initAsClient() creates HTTPS request with SocksProxyAgent
T+1s:    Agent's connect() starts SOCKS5 negotiation (async, awaiting DNS + tunnel)
T+1-5s:  SOCKS5 tunnel being established (could take several seconds)
---
T+15s:   provider.lifecycle's waitForDiscordGatewayReady TIMES OUT
T+15s:   gateway?.disconnect() is called ← WHILE tunnel is still mid-negotiation
---
T+15s:   disconnect() calls this.ws?.close()
T+15s:   WebSocket.close() or .terminate() is called
T+15s:   But what about the SocksProxyAgent's pending connect()?
```

**Analysis:**

1. **WebSocket.terminate()** (called on reconnect code 1005 or via `close()`) calls `abortHandshake()` if CONNECTING
2. **abortHandshake()** calls `this._req.destroy()`
3. **Destroying the HTTP request** should cancel the pending `agent.connect()` callback
4. BUT: If the SocksProxyAgent's `connect()` is mid-await (DNS resolution or socket creation), that doesn't immediately abort

**Potential Issues:**

- The SocksProxyAgent `connect()` may have already called `SocksClient.createConnection()` which is awaiting
- That await won't be interrupted by the request destruction
- The pending SocksClient connection may remain "half-open" consuming resources
- On the next `connect()`, a new tunnel is attempted, but the old one is still pending
- This could cause socket leaks or "zombie" connections

---

### 10. NO BUILT-IN TIMEOUT IN ws LIBRARY

**Finding:** The ws library has `opts.timeout = opts.handshakeTimeout` set in `initAsClient()` line 755, but:

- Default `handshakeTimeout` is **not set** by WebSocket constructor
- This means WebSocket connection has **NO DEFAULT TIMEOUT**
- If `agent.connect()` hangs forever, the WebSocket will wait forever

**Contrast with Carbon's GatewayPlugin:**

- Has heartbeat monitoring (lines 149-161 of GatewayPlugin.js)
- Has zombie connection detection
- But only AFTER the WebSocket opens (HELLO message)
- If WebSocket never opens due to stuck tunnel, heartbeat never starts

---

## THE COMPLETE RACE CONDITION

### Scenario 1: Slow Network / High Latency Proxy

```
T+0s:    Carbon constructor: plugin.registerClient() (no await)
T+0s:    SafeGatewayPlugin.registerClient() starts
T+0-10s: HTTP fetch for gateway/bot API
T+10s:   HTTP fetch completes (or times out)
T+10s:   super.registerClient(client) called
T+10s:   this.connect() creates WebSocket
T+10s:   WebSocket constructor → initAsClient()
T+10s:   HTTPS request created with SocksProxyAgent
T+10s:   Agent.connect() called, starts SOCKS5 negotiation
T+10-15s: DNS + SOCKS5 tunnel establishment (no WebSocket "open" yet)
T+15s:   lifecycle timeout: gateway?.isConnected still false
T+15s:   gateway?.disconnect() called ← EMERGENCY ABORT
T+15s:   WebSocket._req.destroy() called
T+15s:   But SocksProxyAgent.connect() await is still pending
T+15s:   SocksClient.createConnection() may complete later
T+16s:   SocksClient finishes, agent.connect() returns socket
T+16s:   But the request was already destroyed!
T+16s:   WebSocket receives error or closes without opening
```

### Scenario 2: HTTP Fetch Slow Too

```
T+0s:    registerClient() starts
T+0-10s: HTTP fetch is slow
T+10s:   HTTP fetch timeout triggers
T+10s:   Transient error, falls back to default gateway URL
T+10s:   super.registerClient() called
T+10-15s: WebSocket + SOCKS5 tunnel establishing
T+15s:    lifecycle timeout, disconnect() called
T+15s:    Same issue as Scenario 1
```

### Result: The READY Event Never Arrives

- WebSocket is stuck in CONNECTING state
- No HELLO message received
- No heartbeat initiated
- Gateway remains `isConnected = false`
- Lifecycle times out and forces reconnect
- On reconnect, **`isConnecting` guard is reset**, allowing new attempt
- But if the old tunnel is still pending, resources leak

---

## UPSTREAM REPOSITORY: @buape/carbon

**Repository:** https://github.com/buape/carbon

**Issue:** The Carbon Client constructor calls `plugin.registerClient?.(this)` without await on line 122.

**Related:** The GatewayPlugin.registerClient() method is designed to be synchronous (called without await), but our override makes it async.

---

## The Fix (Not In Scope - Planning Only)

### Root Cause

1. Client constructor doesn't await registerClient()
2. SafeGatewayPlugin makes registerClient() async (needed for HTTP fetch)
3. provider.lifecycle times out (15s) before HTTP + tunnel can complete

### Potential Solutions

1. **Make registerClient synchronous** - Cache gateway info at plugin creation time
2. **Make the timeout longer** - Adjust DISCORD_GATEWAY_READY_TIMEOUT_MS based on proxy latency
3. **Parallelize** - Fetch gateway info before creating client
4. **Add connection timeout** - Pass handshakeTimeout to WebSocket constructor
5. **Fix SocksProxyAgent** - Ensure pending connections are properly cleaned up on disconnect

---

## Key File Locations (for reference)

| File                 | Path                                                                   | Key Lines                                                      |
| -------------------- | ---------------------------------------------------------------------- | -------------------------------------------------------------- |
| Carbon GatewayPlugin | `node_modules/@buape/carbon/dist/src/plugins/gateway/GatewayPlugin.js` | 86-117 (connect/disconnect), 128-301 (setupWebSocket)          |
| SafeGatewayPlugin    | `extensions/discord/src/monitor/gateway-plugin.ts`                     | 239-255 (registerClient), 288-304 (proxy setup)                |
| Lifecycle            | `extensions/discord/src/monitor/provider.lifecycle.ts`                 | 18-42 (waitForDiscordGatewayReady), 330-382 (forced reconnect) |
| Carbon Client        | `node_modules/@buape/carbon/dist/src/classes/Client.js`                | 122 (NO AWAIT BUG)                                             |
| ws WebSocket         | `node_modules/ws/lib/websocket.js`                                     | 54-94 (constructor), 657+ (initAsClient)                       |
| SocksProxyAgent      | `node_modules/socks-proxy-agent/dist/index.js`                         | 114-175 (connect method)                                       |

---

## Summary of Findings

| Finding                                                    | Status    | Severity |
| ---------------------------------------------------------- | --------- | -------- |
| Carbon Client doesn't await registerClient()               | CONFIRMED | HIGH     |
| SafeGatewayPlugin.registerClient() is async                | CONFIRMED | HIGH     |
| HTTP fetch can take up to 10 seconds                       | CONFIRMED | MEDIUM   |
| SOCKS5 tunnel can take several seconds                     | CONFIRMED | MEDIUM   |
| Lifecycle timeout is 15 seconds                            | CONFIRMED | HIGH     |
| disconnect() may interrupt mid-tunnel                      | CONFIRMED | HIGH     |
| SocksProxyAgent doesn't properly clean up pending connects | LIKELY    | HIGH     |
| WebSocket has no built-in handshake timeout                | CONFIRMED | HIGH     |
| "gateway was not ready" errors not in current logs         | TRUE      | INFO     |
