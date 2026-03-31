import { wrapFetchWithAbortSignal } from "openclaw/plugin-sdk/infra-runtime";
import { danger } from "openclaw/plugin-sdk/runtime-env";
import type { RuntimeEnv } from "openclaw/plugin-sdk/runtime-env";
import { ProxyAgent, fetch as undiciFetch } from "undici";

const DISCORD_REST_PROXY_ROUTER_INSTALLED = Symbol.for(
  "openclaw.discord.restProxyRouter.installed",
);
const DISCORD_REST_PROXY_ROUTER_MAP = Symbol.for("openclaw.discord.restProxyRouter.map");

type RoutedDiscordFetch = typeof fetch & {
  [DISCORD_REST_PROXY_ROUTER_INSTALLED]?: true;
  [DISCORD_REST_PROXY_ROUTER_MAP]?: Map<string, typeof fetch>;
};

function resolveDiscordProxyFetch(
  proxyUrl: string | undefined,
  runtime: RuntimeEnv,
): typeof fetch | undefined {
  const proxy = proxyUrl?.trim();
  if (!proxy) {
    return undefined;
  }
  try {
    const agent = new ProxyAgent(proxy);
    const fetcher = ((input: RequestInfo | URL, init?: RequestInit) =>
      undiciFetch(input as string | URL, {
        ...(init as Record<string, unknown>),
        dispatcher: agent,
      }) as unknown as Promise<Response>) as typeof fetch;
    runtime.log?.("discord: rest proxy enabled");
    return wrapFetchWithAbortSignal(fetcher);
  } catch (err) {
    runtime.error?.(danger(`discord: invalid rest proxy: ${String(err)}`));
    return undefined;
  }
}

function resolveRequestHeaders(input: RequestInfo | URL, init?: RequestInit): Headers | undefined {
  if (init?.headers) {
    return new Headers(init.headers);
  }
  if (typeof Request !== "undefined" && input instanceof Request) {
    return input.headers;
  }
  return undefined;
}

function resolveDiscordRequestToken(
  input: RequestInfo | URL,
  init?: RequestInit,
): string | undefined {
  const authValue = resolveRequestHeaders(input, init)?.get("authorization")?.trim();
  if (!authValue) {
    return undefined;
  }
  const match = authValue.match(/^(?:bot|bearer)\s+(.+)$/i);
  const token = match?.[1]?.trim();
  return token ? token : undefined;
}

function resolveRequestUrl(input: RequestInfo | URL): URL | null {
  try {
    if (typeof input === "string" || input instanceof URL) {
      return new URL(input.toString());
    }
    if (typeof Request !== "undefined" && input instanceof Request) {
      return new URL(input.url);
    }
  } catch {
    return null;
  }
  return null;
}

function isDiscordApiRequest(input: RequestInfo | URL): boolean {
  const requestUrl = resolveRequestUrl(input);
  if (!requestUrl) {
    return false;
  }
  const host = requestUrl.hostname.toLowerCase();
  const isDiscordHost =
    host === "discord.com" ||
    host.endsWith(".discord.com") ||
    host === "discordapp.com" ||
    host.endsWith(".discordapp.com");
  return isDiscordHost && requestUrl.pathname.startsWith("/api");
}

function installDiscordRestProxyRouter(): RoutedDiscordFetch {
  const currentFetch = globalThis.fetch as RoutedDiscordFetch;
  if (
    currentFetch?.[DISCORD_REST_PROXY_ROUTER_INSTALLED] &&
    currentFetch[DISCORD_REST_PROXY_ROUTER_MAP]
  ) {
    return currentFetch;
  }
  const baseFetch = globalThis.fetch.bind(globalThis) as typeof fetch;
  const proxyFetchByToken = new Map<string, typeof fetch>();
  const routedFetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    if (!isDiscordApiRequest(input)) {
      return baseFetch(input, init);
    }
    const requestToken = resolveDiscordRequestToken(input, init);
    const matchedProxyFetch = requestToken ? proxyFetchByToken.get(requestToken) : undefined;
    if (matchedProxyFetch) {
      return matchedProxyFetch(input, init);
    }
    if (!requestToken && proxyFetchByToken.size === 1) {
      const firstProxyFetch = proxyFetchByToken.values().next().value as typeof fetch | undefined;
      if (firstProxyFetch) {
        return firstProxyFetch(input, init);
      }
    }
    return baseFetch(input, init);
  }) as RoutedDiscordFetch;
  Object.defineProperty(routedFetch, DISCORD_REST_PROXY_ROUTER_INSTALLED, {
    value: true,
    enumerable: false,
    configurable: false,
    writable: false,
  });
  Object.defineProperty(routedFetch, DISCORD_REST_PROXY_ROUTER_MAP, {
    value: proxyFetchByToken,
    enumerable: false,
    configurable: false,
    writable: false,
  });
  globalThis.fetch = routedFetch;
  return routedFetch;
}

export function resolveDiscordRestFetch(
  proxyUrl: string | undefined,
  runtime: RuntimeEnv,
): typeof fetch {
  return resolveDiscordProxyFetch(proxyUrl, runtime) ?? fetch;
}

export function registerDiscordRestProxyRouting(params: {
  token: string;
  restFetch: typeof fetch;
}): void {
  const token = params.token.trim();
  if (!token) {
    return;
  }
  const currentFetch = globalThis.fetch as RoutedDiscordFetch;
  const hasRouter =
    currentFetch?.[DISCORD_REST_PROXY_ROUTER_INSTALLED] &&
    currentFetch[DISCORD_REST_PROXY_ROUTER_MAP];
  if (params.restFetch === fetch) {
    if (hasRouter) {
      currentFetch[DISCORD_REST_PROXY_ROUTER_MAP]?.delete(token);
    }
    return;
  }
  const routedFetch = hasRouter ? currentFetch : installDiscordRestProxyRouter();
  routedFetch[DISCORD_REST_PROXY_ROUTER_MAP]?.set(token, params.restFetch);
}
