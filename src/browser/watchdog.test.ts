import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import {
  ConnectionWatchdog,
  DEFAULT_WATCHDOG_CONFIG,
  createWatchdog,
} from "./watchdog.js";

// Mock detectExistingCDP
vi.mock("./launcher.js", () => ({
  detectExistingCDP: vi.fn(),
}));

import { detectExistingCDP } from "./launcher.js";

const mockDetectExistingCDP = vi.mocked(detectExistingCDP);

describe("watchdog", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    mockDetectExistingCDP.mockReset();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe("DEFAULT_WATCHDOG_CONFIG", () => {
    it("has expected defaults", () => {
      expect(DEFAULT_WATCHDOG_CONFIG.enabled).toBe(true);
      expect(DEFAULT_WATCHDOG_CONFIG.checkInterval).toBe(5000);
      expect(DEFAULT_WATCHDOG_CONFIG.maxRetries).toBe(3);
      expect(DEFAULT_WATCHDOG_CONFIG.autoRestart).toBe(true);
    });
  });

  describe("ConnectionWatchdog", () => {
    it("creates with default config", () => {
      const watchdog = new ConnectionWatchdog(9222);
      const config = watchdog.getConfig();

      expect(config.enabled).toBe(true);
      expect(config.checkInterval).toBe(5000);
    });

    it("merges custom config", () => {
      const watchdog = new ConnectionWatchdog(9222, {
        checkInterval: 10000,
        maxRetries: 5,
      });
      const config = watchdog.getConfig();

      expect(config.checkInterval).toBe(10000);
      expect(config.maxRetries).toBe(5);
      expect(config.enabled).toBe(true); // default
    });

    it("does not start when disabled", () => {
      const watchdog = new ConnectionWatchdog(9222, { enabled: false });
      watchdog.start();

      expect(watchdog.isRunning()).toBe(false);
    });

    it("starts and stops monitoring", async () => {
      mockDetectExistingCDP.mockResolvedValue({
        reachable: true,
        port: 9222,
      });

      const watchdog = new ConnectionWatchdog(9222, { checkInterval: 1000 });
      watchdog.start();

      expect(watchdog.isRunning()).toBe(true);

      // Wait for initial check (0ms triggers immediate check)
      await vi.advanceTimersByTimeAsync(0);

      expect(mockDetectExistingCDP).toHaveBeenCalledTimes(1);

      watchdog.stop();
      expect(watchdog.isRunning()).toBe(false);
    });

    it("detects disconnection and triggers reconnect", async () => {
      const reconnectCallback = vi.fn().mockResolvedValue(true);
      const statusChangeCallback = vi.fn();

      mockDetectExistingCDP
        .mockResolvedValueOnce({ reachable: true, port: 9222 }) // initial
        .mockResolvedValueOnce({ reachable: false, port: 9222 }); // first check - disconnected

      const watchdog = new ConnectionWatchdog(9222, {
        checkInterval: 1000,
        maxRetries: 3,
      });
      watchdog.onReconnect(reconnectCallback);
      watchdog.onStatusChange(statusChangeCallback);
      watchdog.start();

      // Run initial check
      await vi.advanceTimersByTimeAsync(0);

      expect(statusChangeCallback).not.toHaveBeenCalled();

      // Run first interval check - disconnected
      await vi.advanceTimersByTimeAsync(1000);

      expect(reconnectCallback).toHaveBeenCalled();
      expect(statusChangeCallback).toHaveBeenCalledWith(false);
    });

    it("restarts browser after max retries", async () => {
      const restartCallback = vi.fn().mockResolvedValue({
        proc: {} as any,
        pid: 12345,
        cdpPort: 9222,
        userDataDir: "/tmp",
        executable: { kind: "chrome", path: "/usr/bin/chrome" },
        startedAt: Date.now(),
      });

      mockDetectExistingCDP.mockResolvedValue({
        reachable: false,
        port: 9222,
      });

      const watchdog = new ConnectionWatchdog(9222, {
        checkInterval: 50,
        maxRetries: 2,
        autoRestart: true,
      });
      watchdog.onRestart(restartCallback);
      watchdog.start();

      // Initial check
      await vi.advanceTimersByTimeAsync(0);
      // First interval - failure 1
      await vi.advanceTimersByTimeAsync(50);
      // Second interval - failure 2 (max reached)
      await vi.advanceTimersByTimeAsync(50);

      expect(restartCallback).toHaveBeenCalled();
    });

    it("stops when auto-restart is disabled", async () => {
      mockDetectExistingCDP.mockResolvedValue({
        reachable: false,
        port: 9222,
      });

      const watchdog = new ConnectionWatchdog(9222, {
        checkInterval: 50,
        maxRetries: 2,
        autoRestart: false,
      });
      watchdog.start();

      // Initial check
      await vi.advanceTimersByTimeAsync(0);
      // First interval
      await vi.advanceTimersByTimeAsync(50);
      // Second interval - max reached, stops
      await vi.advanceTimersByTimeAsync(50);

      expect(watchdog.isRunning()).toBe(false);
    });

    it("tracks consecutive failures", async () => {
      mockDetectExistingCDP
        .mockResolvedValueOnce({ reachable: true, port: 9222 })
        .mockResolvedValueOnce({ reachable: false, port: 9222 })
        .mockResolvedValueOnce({ reachable: false, port: 9222 });

      const watchdog = new ConnectionWatchdog(9222, {
        checkInterval: 50,
        maxRetries: 10, // high enough to not trigger restart
      });
      watchdog.start();

      expect(watchdog.getConsecutiveFailures()).toBe(0);

      // Initial check - connected
      await vi.advanceTimersByTimeAsync(0);
      expect(watchdog.getConsecutiveFailures()).toBe(0);

      // First interval - disconnected
      await vi.advanceTimersByTimeAsync(50);
      expect(watchdog.getConsecutiveFailures()).toBe(1);

      // Second interval - still disconnected
      await vi.advanceTimersByTimeAsync(50);
      expect(watchdog.getConsecutiveFailures()).toBe(2);

      watchdog.stop();
    });

    it("resets failures on successful connection", async () => {
      mockDetectExistingCDP
        .mockResolvedValueOnce({ reachable: false, port: 9222 })
        .mockResolvedValueOnce({ reachable: true, port: 9222 });

      const watchdog = new ConnectionWatchdog(9222, {
        checkInterval: 50,
        maxRetries: 10,
      });
      watchdog.start();

      // Initial check - disconnected
      await vi.advanceTimersByTimeAsync(0);
      expect(watchdog.getConsecutiveFailures()).toBe(1);

      // Next check - connected
      await vi.advanceTimersByTimeAsync(50);
      expect(watchdog.getConsecutiveFailures()).toBe(0);

      watchdog.stop();
    });

    it("updates config dynamically", () => {
      const watchdog = new ConnectionWatchdog(9222, { checkInterval: 5000 });

      watchdog.updateConfig({ checkInterval: 10000 });

      const config = watchdog.getConfig();
      expect(config.checkInterval).toBe(10000);
    });

    it("manages browser process reference", () => {
      const watchdog = new ConnectionWatchdog(9222);

      expect(watchdog.getBrowserProcess()).toBeNull();

      const process = {
        proc: {} as any,
        pid: 12345,
        cdpPort: 9222,
        userDataDir: "/tmp",
        executable: { kind: "chrome", path: "/usr/bin/chrome" },
        startedAt: Date.now(),
      };

      watchdog.setBrowserProcess(process);
      expect(watchdog.getBrowserProcess()).toBe(process);

      watchdog.setBrowserProcess(null);
      expect(watchdog.getBrowserProcess()).toBeNull();
    });

    it("does not double-start", async () => {
      mockDetectExistingCDP.mockResolvedValue({ reachable: true, port: 9222 });

      const watchdog = new ConnectionWatchdog(9222);
      watchdog.start();
      watchdog.start(); // second call should be ignored

      await vi.advanceTimersByTimeAsync(0);

      // Should only call once despite double start
      expect(mockDetectExistingCDP).toHaveBeenCalledTimes(1);

      watchdog.stop();
    });

    it("exposes resetFailures method", () => {
      const watchdog = new ConnectionWatchdog(9222);
      watchdog.resetFailures();
      expect(watchdog.getConsecutiveFailures()).toBe(0);
    });

    it("checks isConnected", async () => {
      mockDetectExistingCDP.mockResolvedValue({ reachable: true, port: 9222 });

      const watchdog = new ConnectionWatchdog(9222);
      const connected = await watchdog.isConnected();

      expect(connected).toBe(true);
    });
  });

  describe("createWatchdog", () => {
    it("creates a watchdog instance", () => {
      const watchdog = createWatchdog(9222);
      expect(watchdog).toBeInstanceOf(ConnectionWatchdog);
    });
  });
});
