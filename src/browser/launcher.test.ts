import { describe, expect, it, vi } from "vitest";
import {
  DEFAULT_CDP_PORT,
  type CDPInfo,
  type ChromeProcess,
  detectExistingCDP,
  findChromeExecutable,
  resolveCdpConfig,
  terminateChrome,
} from "./launcher.js";

// Mock fetch for CDP detection tests
const mockFetch = vi.fn();
global.fetch = mockFetch;

describe("launcher", () => {
  describe("detectExistingCDP", () => {
    it("returns unreachable when Chrome is not running", async () => {
      mockFetch.mockRejectedValue(new Error("Connection refused"));

      const info = await detectExistingCDP(9222);

      expect(info.reachable).toBe(false);
      expect(info.port).toBe(9222);
    });

    it("returns CDP info when Chrome is running", async () => {
      mockFetch.mockResolvedValue({
        ok: true,
        json: () =>
          Promise.resolve({
            webSocketDebuggerUrl: "ws://127.0.0.1:9222/devtools/browser/xxx",
            Browser: "Chrome/120.0.0.0",
            "User-Agent": "Mozilla/5.0...",
          }),
      });

      const info = await detectExistingCDP(9222);

      expect(info.reachable).toBe(true);
      expect(info.port).toBe(9222);
      expect(info.browserVersion).toBe("Chrome/120.0.0.0");
    });

    it("uses default port when not specified", async () => {
      mockFetch.mockRejectedValue(new Error("Connection refused"));

      const info = await detectExistingCDP();

      expect(info.port).toBe(DEFAULT_CDP_PORT);
    });

    it("handles non-ok response", async () => {
      mockFetch.mockResolvedValue({
        ok: false,
        status: 404,
      });

      const info = await detectExistingCDP(9222);

      expect(info.reachable).toBe(false);
    });

    it("handles invalid JSON response", async () => {
      mockFetch.mockResolvedValue({
        ok: true,
        json: () => Promise.resolve(null),
      });

      const info = await detectExistingCDP(9222);

      expect(info.reachable).toBe(false);
    });
  });

  describe("findChromeExecutable", () => {
    it("returns an executable or null", () => {
      const exe = findChromeExecutable();
      // On CI or systems without Chrome, this may be null
      // We just check it doesn't throw
      expect(exe === null || typeof exe === "object").toBe(true);
    });
  });

  describe("resolveCdpConfig", () => {
    it("returns defaults when no config provided", () => {
      const config = resolveCdpConfig();

      expect(config.port).toBe(DEFAULT_CDP_PORT);
      expect(config.autoLaunch).toBe(true);
      expect(config.profileDir).toContain("browser");
    });

    it("merges provided config with defaults", () => {
      const config = resolveCdpConfig({
        port: 9333,
        autoLaunch: false,
      });

      expect(config.port).toBe(9333);
      expect(config.autoLaunch).toBe(false);
      // profileDir uses default
      expect(config.profileDir).toContain("browser");
    });

    it("uses provided profileDir", () => {
      const config = resolveCdpConfig({
        profileDir: "/custom/profile",
      });

      expect(config.profileDir).toBe("/custom/profile");
    });
  });

  describe("terminateChrome", () => {
    it("handles already exited process", async () => {
      const mockProc = {
        exitCode: 0,
        kill: vi.fn(),
      } as unknown as ChromeProcess["proc"];

      const process: ChromeProcess = {
        proc: mockProc,
        pid: 12345,
        cdpPort: 9222,
        userDataDir: "/tmp/profile",
        executable: { kind: "chrome", path: "/usr/bin/google-chrome" },
        startedAt: Date.now(),
      };

      await terminateChrome(process);

      expect(mockProc.kill).not.toHaveBeenCalled();
    });

    it("sends SIGTERM to running process", async () => {
      // Mock a process that exits after SIGTERM
      let exitCode: number | null = null;
      const mockProc = {
        get exitCode() {
          return exitCode;
        },
        kill: vi.fn((signal: string) => {
          if (signal === "SIGTERM") {
            setTimeout(() => {
              exitCode = 0;
            }, 50);
          }
        }),
      } as unknown as ChromeProcess["proc"];

      const process: ChromeProcess = {
        proc: mockProc,
        pid: 12345,
        cdpPort: 9222,
        userDataDir: "/tmp/profile",
        executable: { kind: "chrome", path: "/usr/bin/google-chrome" },
        startedAt: Date.now(),
      };

      await terminateChrome(process, 1000);

      expect(mockProc.kill).toHaveBeenCalledWith("SIGTERM");
    });
  });

  describe("types", () => {
    it("CDPInfo has expected shape", () => {
      const info: CDPInfo = {
        reachable: true,
        webSocketDebuggerUrl: "ws://127.0.0.1:9222/devtools/browser/xxx",
        browserVersion: "Chrome/120.0.0.0",
        userAgent: "Mozilla/5.0...",
        port: 9222,
      };

      expect(info.reachable).toBe(true);
      expect(info.port).toBe(9222);
    });

    it("ChromeProcess has expected shape", () => {
      const proc: ChromeProcess = {
        proc: {} as ChromeProcess["proc"],
        pid: 12345,
        cdpPort: 9222,
        userDataDir: "/tmp/profile",
        executable: { kind: "chrome", path: "/usr/bin/google-chrome" },
        startedAt: Date.now(),
      };

      expect(proc.pid).toBe(12345);
      expect(proc.cdpPort).toBe(9222);
    });
  });
});
