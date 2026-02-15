/**
 * Connection Watchdog - Monitor browser connection and auto-reconnect.
 *
 * Provides continuous monitoring of CDP connection status,
 * automatic reconnection on disconnect, and browser restart
 * after repeated failures.
 */

import { createSubsystemLogger } from "../logging/subsystem.js";
import type { BrowserWatchdogConfig } from "../config/types.browser.js";
import { detectExistingCDP } from "./launcher.js";
import type { ChromeProcess } from "./launcher.js";

const log = createSubsystemLogger("browser").child("watchdog");

/** Default watchdog configuration. */
export const DEFAULT_WATCHDOG_CONFIG: Required<BrowserWatchdogConfig> = {
  enabled: true,
  checkInterval: 5000,
  maxRetries: 3,
  autoRestart: true,
};

/** Callback type for reconnection attempts. */
export type ReconnectCallback = () => Promise<boolean>;

/** Callback type for browser restart. */
export type RestartCallback = () => Promise<ChromeProcess | null>;

/** Callback type for connection status changes. */
export type StatusChangeCallback = (connected: boolean) => void;

/**
 * Connection Watchdog for browser automation.
 *
 * Monitors the CDP connection at regular intervals, attempts to reconnect
 * when disconnected, and can restart the browser after repeated failures.
 */
export class ConnectionWatchdog {
  private config: Required<BrowserWatchdogConfig>;
  private cdpPort: number;
  private checkTimer: ReturnType<typeof setInterval> | null = null;
  private consecutiveFailures = 0;
  private isReconnecting = false;
  private lastConnectedState = true;
  private reconnectCallback: ReconnectCallback | null = null;
  private restartCallback: RestartCallback | null = null;
  private statusChangeCallback: StatusChangeCallback | null = null;
  private browserProcess: ChromeProcess | null = null;

  constructor(
    cdpPort: number,
    config?: BrowserWatchdogConfig,
  ) {
    this.cdpPort = cdpPort;
    this.config = { ...DEFAULT_WATCHDOG_CONFIG, ...config };
  }

  /**
   * Set the reconnection callback.
   * Called when the watchdog detects a disconnect and needs to reconnect.
   */
  onReconnect(callback: ReconnectCallback): void {
    this.reconnectCallback = callback;
  }

  /**
   * Set the browser restart callback.
   * Called when max retries exceeded and browser needs to be restarted.
   */
  onRestart(callback: RestartCallback): void {
    this.restartCallback = callback;
  }

  /**
   * Set the status change callback.
   * Called when connection status changes (connected <-> disconnected).
   */
  onStatusChange(callback: StatusChangeCallback): void {
    this.statusChangeCallback = callback;
  }

  /**
   * Set the current browser process reference.
   * Used for tracking the managed browser instance.
   */
  setBrowserProcess(process: ChromeProcess | null): void {
    this.browserProcess = process;
  }

  /**
   * Get the current browser process.
   */
  getBrowserProcess(): ChromeProcess | null {
    return this.browserProcess;
  }

  /**
   * Start the watchdog monitoring.
   */
  start(): void {
    if (!this.config.enabled) {
      log.info("Watchdog disabled, not starting");
      return;
    }

    if (this.checkTimer) {
      log.warn("Watchdog already running");
      return;
    }

    log.info(`Starting watchdog (port=${this.cdpPort}, interval=${this.config.checkInterval}ms)`);
    this.consecutiveFailures = 0;
    this.lastConnectedState = true;

    // Run initial check immediately
    this.checkConnection().catch((err) => {
      log.error(`Initial connection check failed: ${String(err)}`);
    });

    // Schedule periodic checks
    this.checkTimer = setInterval(() => {
      this.checkConnection().catch((err) => {
        log.error(`Connection check failed: ${String(err)}`);
      });
    }, this.config.checkInterval);
  }

  /**
   * Stop the watchdog monitoring.
   */
  stop(): void {
    if (this.checkTimer) {
      clearInterval(this.checkTimer);
      this.checkTimer = null;
      log.info("Watchdog stopped");
    }
  }

  /**
   * Check if the watchdog is currently running.
   */
  isRunning(): boolean {
    return this.checkTimer !== null;
  }

  /**
   * Get the current connection status.
   */
  async isConnected(): Promise<boolean> {
    const info = await detectExistingCDP(this.cdpPort);
    return info.reachable;
  }

  /**
   * Get current consecutive failure count.
   */
  getConsecutiveFailures(): number {
    return this.consecutiveFailures;
  }

  /**
   * Reset the consecutive failure counter.
   */
  resetFailures(): void {
    this.consecutiveFailures = 0;
  }

  /**
   * Perform a connection check.
   */
  private async checkConnection(): Promise<void> {
    // Skip if already reconnecting
    if (this.isReconnecting) {
      return;
    }

    const info = await detectExistingCDP(this.cdpPort);
    const connected = info.reachable;

    // Notify status change
    if (connected !== this.lastConnectedState) {
      this.lastConnectedState = connected;
      if (this.statusChangeCallback) {
        this.statusChangeCallback(connected);
      }
    }

    if (connected) {
      // Connection is good
      this.consecutiveFailures = 0;
      return;
    }

    // Connection lost
    log.warn(`Connection lost (port=${this.cdpPort})`);
    this.consecutiveFailures++;

    if (this.consecutiveFailures >= this.config.maxRetries) {
      log.error(
        `Max retries (${this.config.maxRetries}) exceeded, attempting browser restart`
      );

      if (this.config.autoRestart) {
        await this.restartBrowser();
      } else {
        log.warn("Auto-restart disabled, giving up");
        this.stop();
      }
      return;
    }

    // Attempt reconnection
    await this.reconnect();
  }

  /**
   * Attempt to reconnect to the browser.
   */
  private async reconnect(): Promise<void> {
    if (!this.reconnectCallback) {
      log.warn("No reconnect callback configured");
      return;
    }

    this.isReconnecting = true;
    try {
      log.info(`Attempting reconnect (${this.consecutiveFailures}/${this.config.maxRetries})`);
      const success = await this.reconnectCallback();

      if (success) {
        log.info("Reconnect successful");
        this.consecutiveFailures = 0;
      } else {
        log.warn("Reconnect failed");
      }
    } catch (err) {
      log.error(`Reconnect error: ${String(err)}`);
    } finally {
      this.isReconnecting = false;
    }
  }

  /**
   * Restart the browser.
   */
  private async restartBrowser(): Promise<void> {
    if (!this.restartCallback) {
      log.warn("No restart callback configured");
      return;
    }

    this.isReconnecting = true;
    try {
      log.info("Restarting browser");
      const process = await this.restartCallback();

      if (process) {
        this.browserProcess = process;
        this.consecutiveFailures = 0;
        log.info("Browser restarted successfully");
      } else {
        log.error("Browser restart failed");
        this.stop();
      }
    } catch (err) {
      log.error(`Browser restart error: ${String(err)}`);
      this.stop();
    } finally {
      this.isReconnecting = false;
    }
  }

  /**
   * Update the watchdog configuration.
   */
  updateConfig(config: Partial<BrowserWatchdogConfig>): void {
    this.config = { ...this.config, ...config };

    // Restart timer if interval changed
    if (config.checkInterval !== undefined && this.checkTimer) {
      clearInterval(this.checkTimer);
      this.checkTimer = setInterval(() => {
        this.checkConnection().catch((err) => {
          log.error(`Connection check failed: ${String(err)}`);
        });
      }, this.config.checkInterval);
    }
  }

  /**
   * Get the current configuration.
   */
  getConfig(): Required<BrowserWatchdogConfig> {
    return { ...this.config };
  }
}

/**
 * Create a watchdog instance with default configuration.
 */
export function createWatchdog(
  cdpPort: number,
  config?: BrowserWatchdogConfig,
): ConnectionWatchdog {
  return new ConnectionWatchdog(cdpPort, config);
}
