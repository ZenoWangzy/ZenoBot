import { describe, expect, it } from "vitest";
import type {
  BrowserConfig,
  BrowserCdpConfig,
  BrowserConnectionMode,
  BrowserTimeoutConfig,
  BrowserWatchdogConfig,
} from "./types.browser.js";

describe("types.browser", () => {
  describe("BrowserConnectionMode", () => {
    it("accepts valid connection modes", () => {
      const modes: BrowserConnectionMode[] = ["auto", "cdp-direct", "extension-relay"];
      expect(modes).toHaveLength(3);
    });
  });

  describe("BrowserCdpConfig", () => {
    it("accepts valid CDP config", () => {
      const config: BrowserCdpConfig = {
        port: 9222,
        autoLaunch: true,
        profileDir: "~/.openclaw/browser-profiles/default",
      };
      expect(config.port).toBe(9222);
      expect(config.autoLaunch).toBe(true);
    });

    it("allows partial config", () => {
      const config: BrowserCdpConfig = {
        port: 9223,
      };
      expect(config.port).toBe(9223);
      expect(config.autoLaunch).toBeUndefined();
    });
  });

  describe("BrowserWatchdogConfig", () => {
    it("accepts valid watchdog config", () => {
      const config: BrowserWatchdogConfig = {
        enabled: true,
        checkInterval: 5000,
        maxRetries: 3,
        autoRestart: true,
      };
      expect(config.enabled).toBe(true);
      expect(config.checkInterval).toBe(5000);
      expect(config.maxRetries).toBe(3);
      expect(config.autoRestart).toBe(true);
    });

    it("allows partial config", () => {
      const config: BrowserWatchdogConfig = {
        enabled: false,
      };
      expect(config.enabled).toBe(false);
      expect(config.checkInterval).toBeUndefined();
    });
  });

  describe("BrowserTimeoutConfig", () => {
    it("accepts valid timeout config", () => {
      const config: BrowserTimeoutConfig = {
        connect: 60000,
        operation: 30000,
        idle: 300000,
      };
      expect(config.connect).toBe(60000);
      expect(config.operation).toBe(30000);
      expect(config.idle).toBe(300000);
    });
  });

  describe("BrowserConfig", () => {
    it("accepts full config with new fields", () => {
      const config: BrowserConfig = {
        enabled: true,
        mode: "auto",
        cdp: {
          port: 9222,
          autoLaunch: true,
          profileDir: "~/.openclaw/browser-profiles/default",
        },
        watchdog: {
          enabled: true,
          checkInterval: 5000,
          maxRetries: 3,
          autoRestart: true,
        },
        timeouts: {
          connect: 60000,
          operation: 30000,
          idle: 300000,
        },
      };
      expect(config.mode).toBe("auto");
      expect(config.cdp?.port).toBe(9222);
      expect(config.watchdog?.enabled).toBe(true);
      expect(config.timeouts?.connect).toBe(60000);
    });

    it("accepts minimal config", () => {
      const config: BrowserConfig = {
        enabled: true,
      };
      expect(config.enabled).toBe(true);
      expect(config.mode).toBeUndefined();
    });

    it("accepts cdp-direct mode", () => {
      const config: BrowserConfig = {
        mode: "cdp-direct",
      };
      expect(config.mode).toBe("cdp-direct");
    });

    it("accepts extension-relay mode", () => {
      const config: BrowserConfig = {
        mode: "extension-relay",
      };
      expect(config.mode).toBe("extension-relay");
    });
  });
});
