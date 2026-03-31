import { afterEach, describe, expect, it, vi } from "vitest";
import { registerDiscordRestProxyRouting, resolveDiscordRestFetch } from "./rest-fetch.js";

const { undiciFetchMock, proxyAgentSpy } = vi.hoisted(() => ({
  undiciFetchMock: vi.fn(),
  proxyAgentSpy: vi.fn(),
}));

vi.mock("undici", () => {
  class ProxyAgent {
    proxyUrl: string;
    constructor(proxyUrl: string) {
      if (proxyUrl === "bad-proxy") {
        throw new Error("bad proxy");
      }
      this.proxyUrl = proxyUrl;
      proxyAgentSpy(proxyUrl);
    }
  }
  return {
    ProxyAgent,
    fetch: undiciFetchMock,
  };
});

describe("resolveDiscordRestFetch", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    undiciFetchMock.mockReset();
    proxyAgentSpy.mockClear();
  });

  it("uses undici proxy fetch when a proxy URL is configured", async () => {
    const runtime = {
      log: vi.fn(),
      error: vi.fn(),
      exit: vi.fn(),
    } as const;
    undiciFetchMock.mockClear().mockResolvedValue(new Response("ok", { status: 200 }));
    proxyAgentSpy.mockClear();
    const fetcher = resolveDiscordRestFetch("http://proxy.test:8080", runtime);

    await fetcher("https://discord.com/api/v10/oauth2/applications/@me");

    expect(proxyAgentSpy).toHaveBeenCalledWith("http://proxy.test:8080");
    expect(undiciFetchMock).toHaveBeenCalledWith(
      "https://discord.com/api/v10/oauth2/applications/@me",
      expect.objectContaining({
        dispatcher: expect.objectContaining({ proxyUrl: "http://proxy.test:8080" }),
      }),
    );
    expect(runtime.log).toHaveBeenCalledWith("discord: rest proxy enabled");
    expect(runtime.error).not.toHaveBeenCalled();
  });

  it("falls back to global fetch when proxy URL is invalid", async () => {
    const runtime = {
      log: vi.fn(),
      error: vi.fn(),
      exit: vi.fn(),
    } as const;
    const fetcher = resolveDiscordRestFetch("bad-proxy", runtime);

    expect(fetcher).toBe(fetch);
    expect(runtime.error).toHaveBeenCalled();
    expect(runtime.log).not.toHaveBeenCalled();
  });

  it("routes Discord REST calls for the registered token through proxy fetch", async () => {
    const runtime = {
      log: vi.fn(),
      error: vi.fn(),
      exit: vi.fn(),
    } as const;
    const directFetch = vi.fn(async () => new Response("direct", { status: 200 }));
    vi.stubGlobal("fetch", directFetch as unknown as typeof fetch);
    undiciFetchMock.mockResolvedValue(new Response("proxied", { status: 200 }));

    const proxyFetch = resolveDiscordRestFetch("http://proxy.test:8080", runtime);
    registerDiscordRestProxyRouting({
      token: "token-123",
      restFetch: proxyFetch,
    });

    await globalThis.fetch("https://discord.com/api/v10/applications/@me", {
      headers: {
        Authorization: "Bot token-123",
      },
    });

    expect(undiciFetchMock).toHaveBeenCalledWith(
      "https://discord.com/api/v10/applications/@me",
      expect.objectContaining({
        dispatcher: expect.objectContaining({ proxyUrl: "http://proxy.test:8080" }),
      }),
    );
    expect(directFetch).not.toHaveBeenCalled();
  });

  it("falls back to the original global fetch for non-Discord hosts", async () => {
    const runtime = {
      log: vi.fn(),
      error: vi.fn(),
      exit: vi.fn(),
    } as const;
    const directFetch = vi.fn(async () => new Response("direct", { status: 200 }));
    vi.stubGlobal("fetch", directFetch as unknown as typeof fetch);
    undiciFetchMock.mockResolvedValue(new Response("proxied", { status: 200 }));

    const proxyFetch = resolveDiscordRestFetch("http://proxy.test:8080", runtime);
    registerDiscordRestProxyRouting({
      token: "token-123",
      restFetch: proxyFetch,
    });

    await globalThis.fetch("https://example.com/healthz");

    expect(directFetch).toHaveBeenCalledTimes(1);
    expect(undiciFetchMock).not.toHaveBeenCalled();
  });

  it("removes token routing when the configured rest fetch falls back to global fetch", async () => {
    const runtime = {
      log: vi.fn(),
      error: vi.fn(),
      exit: vi.fn(),
    } as const;
    const directFetch = vi.fn(async () => new Response("direct", { status: 200 }));
    vi.stubGlobal("fetch", directFetch as unknown as typeof fetch);
    undiciFetchMock.mockResolvedValue(new Response("proxied", { status: 200 }));

    const proxyFetch = resolveDiscordRestFetch("http://proxy.test:8080", runtime);
    registerDiscordRestProxyRouting({
      token: "token-123",
      restFetch: proxyFetch,
    });

    registerDiscordRestProxyRouting({
      token: "token-123",
      restFetch: fetch,
    });

    await globalThis.fetch("https://discord.com/api/v10/applications/@me", {
      headers: {
        Authorization: "Bot token-123",
      },
    });

    expect(directFetch).toHaveBeenCalledTimes(1);
  });
});
