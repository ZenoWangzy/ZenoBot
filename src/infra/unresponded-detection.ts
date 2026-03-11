/**
 * Unresponded message detection helper.
 *
 * Detects when user messages have not received a response within a timeout period.
 */

import { parseDurationMs } from "../cli/parse-duration.js";
import type { SessionEntry } from "../config/sessions/types.js";

export type UnrespondedConfig = {
  /** Enable unresponded detection (default: false) */
  enabled?: boolean;
  /** Timeout duration string (e.g., '5m', '10m', '1h'). Default: 10m */
  timeout?: string;
  /** Cooldown duration string (e.g., '1m', '5m'). Default: 5m */
  cooldown?: string;
};

export type UnrespondedCheckResult = {
  /** Indicates unresponded message was detected */
  hasUnresponded: true;
  /** Elapsed time in ms since last inbound message */
  elapsedMs: number;
  /** Preview of the last inbound message */
  preview?: string;
};

const DEFAULT_TIMEOUT_MS = 10 * 60 * 1000; // 10 minutes
const DEFAULT_COOLDOWN_MS = 5 * 60 * 1000; // 5 minutes

/**
 * Check if session has unresponded messages.
 *
 * @param config - Unresponded detection config
 * @param session - Session entry to check
 * @returns UnrespondedCheckResult if unresponded, null otherwise
 */
export function checkUnrespondedMessages(
  config: UnrespondedConfig,
  session: SessionEntry,
): UnrespondedCheckResult | null {
  if (!config.enabled) {
    return null;
  }

  const lastInbound = session.lastInboundAt;
  if (!lastInbound) {
    return null;
  }

  const lastOutbound = session.lastOutboundAt ?? 0;
  if (lastInbound <= lastOutbound) {
    return null;
  }

  const timeoutMs = config.timeout
    ? parseDurationMs(config.timeout, { defaultUnit: "m" })
    : DEFAULT_TIMEOUT_MS;

  const elapsedMs = Date.now() - lastInbound;
  if (elapsedMs < timeoutMs) {
    return null;
  }

  // Cooldown check to prevent repeated wake-ups
  const cooldownMs = config.cooldown
    ? parseDurationMs(config.cooldown, { defaultUnit: "m" })
    : DEFAULT_COOLDOWN_MS;
  const lastWake = session.lastUnrespondedWakeAt ?? 0;
  if (Date.now() - lastWake < cooldownMs) {
    return null;
  }

  return {
    hasUnresponded: true,
    elapsedMs,
    preview: session.lastInboundPreview,
  };
}
