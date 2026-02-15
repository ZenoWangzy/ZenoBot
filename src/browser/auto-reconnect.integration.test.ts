/**
 * Integration tests for browser auto-reconnect functionality.
 *
 * Tests the interaction between:
 * - BrowserLauncher (detectExistingCDP, launchWithCDP)
 * - ConnectionWatchdog (monitoring, auto-reconnect)
 * - SessionStateRecovery (state snapshot and restore)
 * - pw-session (connectWithFallback)
 */

import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import {
  detectExistingCDP,
  launchWithCDP,
  resolveCdpConfig,
  terminateChrome,
  DEFAULT_CDP_PORT,
  type CDPInfo,
  type ChromeProcess,
} from "./launcher.js";
import {
  ConnectionWatchdog,
  createWatchdog,
  DEFAULT_WATCHDOG_CONFIG,
} from "./watchdog.js";
import {
  SessionStateRecovery,
  createSessionStateRecovery,
  DEFAULT_TIMEOUT_CONFIG,
  type SessionSnapshot,
} from "./recovery.js";

// Mock fetch for CDP detection
const mockFetch = vi.fn();
global.fetch = mockFetch;

describe("Auto-reconnect Integration", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    mockFetch.mockReset();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe("Launcher + Watchdog Integration", () => {
    it("detects existing CDP and creates watchdog", async () => {
      // Mock CDP is running
      mockFetch.mockResolvedValue({
        ok: true,
        json: () =>
          Promise.resolve({
            webSocketDebuggerUrl: "ws://127.0.0.1:9222/devtools/browser/xxx",
            Browser: "Chrome/120.0.0.0",
          }),
      });

      const cdpInfo = await detectExistingCDP(9222);
      expect(cdpInfo.reachable).toBe(true);

      // Create watchdog for the detected port
      const watchdog = createWatchdog(cdpInfo.port);
      expect(watchdog).toBeInstanceOf(ConnectionWatchdog);
      expect(watchdog.getConfig().enabled).toBe(true);
    });

    it("watchdog monitors CDP connection status", async () => {
      mockFetch
        .mockResolvedValueOnce({
          ok: true,
          json: () =>
            Promise.resolve({
              webSocketDebuggerUrl: "ws://127.0.0.1:9222/devtools/browser/xxx",
              Browser: "Chrome/120.0.0.0",
            }),
        })
        .mockResolvedValueOnce({
          ok: true,
          json: () =>
            Promise.resolve({
              webSocketDebuggerUrl: "ws://127.0.0.1:9222/devtools/browser/xxx",
              Browser: "Chrome/120.0.0.0",
            }),
        });

      const statusChanges: boolean[] = [];
      const watchdog = createWatchdog(9222, { checkInterval: 100 });
      watchdog.onStatusChange((connected) => {
        statusChanges.push(connected);
      });
      watchdog.start();

      // Initial check
      await vi.advanceTimersByTimeAsync(0);
      expect(statusChanges.length).toBe(0); // No change on first connect

      // Next check - still connected
      await vi.advanceTimersByTimeAsync(100);
      expect(statusChanges.length).toBe(0);

      watchdog.stop();
    });
  });

  describe("Watchdog + Recovery Integration", () => {
    it("saves state before reconnection attempt", async () => {
      const recovery = createSessionStateRecovery();
      const snapshot: SessionSnapshot = {
        activeTabUrl: "https://example.com/page",
        activeTabTitle: "Example Page",
        scrollPosition: { x: 0, y: 500 },
        formData: { username: "test" },
        timestamp: Date.now(),
      };

      recovery.saveSnapshot(snapshot);

      mockFetch.mockResolvedValue({
        ok: false,
      });

      const reconnectAttempts: number[] = [];
      const watchdog = createWatchdog(9222, {
        checkInterval: 100,
        maxRetries: 5,
      });

      watchdog.onReconnect(async () => {
        reconnectAttempts.push(Date.now());
        // Simulate checking recovery state during reconnect
        const recoveryData = recovery.getRecoveryData();
        expect(recoveryData).not.toBeNull();
        expect(recoveryData?.activeTabUrl).toBe(snapshot.activeTabUrl);
        return true;
      });

      watchdog.start();

      // Trigger disconnect and reconnect
      await vi.advanceTimersByTimeAsync(0);
      await vi.advanceTimersByTimeAsync(100);

      expect(reconnectAttempts.length).toBeGreaterThan(0);

      watchdog.stop();
    });

    it("clears recovery after successful restore", async () => {
      const recovery = createSessionStateRecovery();
      const snapshot: SessionSnapshot = {
        activeTabUrl: "https://example.com",
        activeTabTitle: "Example",
        scrollPosition: { x: 0, y: 0 },
        formData: {},
        timestamp: Date.now(),
      };

      recovery.saveSnapshot(snapshot);
      expect(recovery.getSnapshot()).not.toBeNull();

      // Simulate restore and clear
      recovery.clearSnapshot();
      expect(recovery.getSnapshot()).toBeNull();
    });
  });

  describe("End-to-End Reconnection Flow", () => {
    it("simulates full disconnect -> reconnect cycle", async () => {
      const events: string[] = [];

      // Setup recovery
      const recovery = createSessionStateRecovery();
      recovery.saveSnapshot({
        activeTabUrl: "https://example.com",
        activeTabTitle: "Example",
        scrollPosition: { x: 100, y: 200 },
        formData: { search: "test" },
        timestamp: Date.now(),
      });
      events.push("state_saved");

      // Mock initial connection, then disconnect
      let connectionState = true;
      mockFetch.mockImplementation(async () => {
        if (connectionState) {
          return {
            ok: true,
            json: () =>
              Promise.resolve({
                webSocketDebuggerUrl: "ws://127.0.0.1:9222/devtools/browser/xxx",
                Browser: "Chrome/120.0.0.0",
              }),
          };
        }
        throw new Error("Connection refused");
      });

      // Setup watchdog
      const watchdog = createWatchdog(9222, {
        checkInterval: 50,
        maxRetries: 3,
      });

      watchdog.onStatusChange((connected) => {
        events.push(connected ? "connected" : "disconnected");
      });

      watchdog.onReconnect(async () => {
        events.push("reconnect_attempt");
        // Simulate successful reconnect
        connectionState = true;
        return true;
      });

      watchdog.start();

      // Initial check - connected
      await vi.advanceTimersByTimeAsync(0);
      expect(events).toContain("state_saved");

      // Simulate disconnect
      connectionState = false;
      await vi.advanceTimersByTimeAsync(50);

      // Should detect disconnect and attempt reconnect
      expect(events).toContain("disconnected");
      expect(events).toContain("reconnect_attempt");

      watchdog.stop();
    });

    it("restarts browser after max retries", async () => {
      mockFetch.mockResolvedValue({
        ok: false,
      });

      const events: string[] = [];
      const watchdog = createWatchdog(9222, {
        checkInterval: 50,
        maxRetries: 2,
        autoRestart: true,
      });

      watchdog.onReconnect(async () => {
        events.push("reconnect");
        return false;
      });

      watchdog.onRestart(async () => {
        events.push("restart");
        return {
          proc: {} as ChromeProcess["proc"],
          pid: 12345,
          cdpPort: 9222,
          userDataDir: "/tmp",
          executable: { kind: "chrome", path: "/usr/bin/chrome" },
          startedAt: Date.now(),
        };
      });

      watchdog.start();

      // Run through failure cycles
      await vi.advanceTimersByTimeAsync(0); // failure 1
      await vi.advanceTimersByTimeAsync(50); // failure 2 -> max reached

      expect(events).toContain("restart");

      watchdog.stop();
    });
  });

  describe("Configuration Integration", () => {
    it("applies consistent timeout configuration", () => {
      const cdpConfig = resolveCdpConfig({
        port: 9333,
        autoLaunch: false,
      });

      const watchdogConfig = {
        ...DEFAULT_WATCHDOG_CONFIG,
        checkInterval: 3000,
      };

      const recoveryOptions = {
        maxSnapshotAge: DEFAULT_TIMEOUT_CONFIG.idle,
      };

      // Verify configurations are consistent
      expect(cdpConfig.port).toBe(9333);
      expect(watchdogConfig.checkInterval).toBe(3000);
      expect(recoveryOptions.maxSnapshotAge).toBe(300000);
    });

    it("creates all components with matching configuration", () => {
      const port = 9222;
      const checkInterval = 5000;

      const watchdog = createWatchdog(port, { checkInterval });
      const recovery = createSessionStateRecovery({
        maxSnapshotAge: 60000,
      });

      expect(watchdog.getConfig().checkInterval).toBe(checkInterval);
      expect(recovery.getOptions().maxSnapshotAge).toBe(60000);
    });
  });

  describe("Error Handling Integration", () => {
    it("handles launcher errors gracefully in watchdog", async () => {
      mockFetch.mockRejectedValue(new Error("Network error"));

      const events: string[] = [];
      const watchdog = createWatchdog(9222, {
        checkInterval: 50,
        maxRetries: 2,
      });

      watchdog.onReconnect(async () => {
        events.push("reconnect");
        return false;
      });

      watchdog.onRestart(async () => {
        events.push("restart");
        return null; // Simulate restart failure
      });

      watchdog.start();

      // Run through failure cycles
      for (let i = 0; i < 5; i++) {
        await vi.advanceTimersByTimeAsync(50);
      }

      // Should have attempted reconnects and restart
      expect(events.length).toBeGreaterThan(0);

      // Watchdog should stop after restart failure
      expect(watchdog.isRunning()).toBe(false);
    });

    it("recovery handles missing snapshot gracefully", () => {
      const recovery = createSessionStateRecovery();

      // No snapshot saved
      expect(recovery.getRecoveryData()).toBeNull();
      expect(recovery.isSnapshotValid()).toBe(false);

      // Clear should not throw
      recovery.clearSnapshot();
    });
  });
});
