import type { EventEmitter } from "node:events";
import type { RuntimeEnv } from "../runtime.js";
import { logVerbose, danger } from "../globals.js";

type GatewayEmitter = Pick<EventEmitter, "on" | "removeListener">;

const INFO_DEBUG_MARKERS = [
  "WebSocket connection closed",
  "Reconnecting with backoff",
  "Attempting resume with backoff",
  "Heartbeat acknowledged",
  "Received HELLO",
];

const ERROR_DEBUG_MARKERS = [
  "failed to connect",
  "connection reset",
  "ECONNRESET",
  "ETIMEDOUT",
];

const shouldPromoteGatewayDebug = (message: string) =>
  INFO_DEBUG_MARKERS.some((marker) => message.includes(marker));

const shouldPromoteGatewayError = (message: string) =>
  ERROR_DEBUG_MARKERS.some((marker) => message.includes(marker));

const formatGatewayMetrics = (metrics: unknown) => {
  if (metrics === null || metrics === undefined) {
    return String(metrics);
  }
  if (typeof metrics === "string") {
    return metrics;
  }
  if (typeof metrics === "number" || typeof metrics === "boolean" || typeof metrics === "bigint") {
    return String(metrics);
  }
  try {
    return JSON.stringify(metrics);
  } catch {
    return "[unserializable metrics]";
  }
};

/**
 * Connection health monitor for Discord gateway.
 * Tracks last activity and detects zombie connections.
 */
export class DiscordGatewayHealthMonitor {
  private lastActivityTime = Date.now();
  private healthCheckTimer: ReturnType<typeof setInterval> | null = null;
  private readonly checkIntervalMs: number;
  private readonly zombieThresholdMs: number;
  private onZombieDetected: (() => void) | null = null;

  constructor(options?: { checkIntervalMs?: number; zombieThresholdMs?: number }) {
    this.checkIntervalMs = options?.checkIntervalMs ?? 60000; // Check every 60s
    this.zombieThresholdMs = options?.zombieThresholdMs ?? 180000; // 3 minutes without activity
  }

  recordActivity(): void {
    this.lastActivityTime = Date.now();
  }

  setOnZombieDetected(callback: () => void): void {
    this.onZombieDetected = callback;
  }

  start(): void {
    if (this.healthCheckTimer) {
      return;
    }

    this.healthCheckTimer = setInterval(() => {
      const timeSinceLastActivity = Date.now() - this.lastActivityTime;
      if (timeSinceLastActivity > this.zombieThresholdMs) {
        logVerbose(`discord gateway: zombie connection detected (${Math.round(timeSinceLastActivity / 1000)}s since last activity)`);
        this.onZombieDetected?.();
      }
    }, this.checkIntervalMs);
  }

  stop(): void {
    if (this.healthCheckTimer) {
      clearInterval(this.healthCheckTimer);
      this.healthCheckTimer = null;
    }
  }

  getLastActivityTime(): number {
    return this.lastActivityTime;
  }
}

export function attachDiscordGatewayLogging(params: {
  emitter?: GatewayEmitter;
  runtime: RuntimeEnv;
  healthMonitor?: DiscordGatewayHealthMonitor;
}) {
  const { emitter, runtime, healthMonitor } = params;
  if (!emitter) {
    return () => {};
  }

  const onGatewayDebug = (msg: unknown) => {
    const message = String(msg);
    logVerbose(`discord gateway: ${message}`);

    // Record activity for health monitoring
    healthMonitor?.recordActivity();

    if (shouldPromoteGatewayDebug(message)) {
      runtime.log?.(`discord gateway: ${message}`);
    }

    // Promote error-level debug messages
    if (shouldPromoteGatewayError(message)) {
      runtime.error?.(danger(`discord gateway: ${message}`));
    }
  };

  const onGatewayWarning = (warning: unknown) => {
    logVerbose(`discord gateway warning: ${String(warning)}`);
    healthMonitor?.recordActivity();
  };

  const onGatewayMetrics = (metrics: unknown) => {
    logVerbose(`discord gateway metrics: ${formatGatewayMetrics(metrics)}`);
    healthMonitor?.recordActivity();
  };

  emitter.on("debug", onGatewayDebug);
  emitter.on("warning", onGatewayWarning);
  emitter.on("metrics", onGatewayMetrics);

  return () => {
    emitter.removeListener("debug", onGatewayDebug);
    emitter.removeListener("warning", onGatewayWarning);
    emitter.removeListener("metrics", onGatewayMetrics);
  };
}
