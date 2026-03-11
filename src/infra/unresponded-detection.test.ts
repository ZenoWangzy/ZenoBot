import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { SessionEntry } from "../config/sessions/types.js";
import { checkUnrespondedMessages } from "./unresponded-detection.js";

describe("checkUnrespondedMessages", () => {
  const now = 1700000000000;

  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(now);
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  const createSession = (partial: Partial<SessionEntry> = {}): SessionEntry => ({
    sessionId: "test",
    updatedAt: now,
    ...partial,
  });

  describe("when disabled", () => {
    it("returns null when enabled is false", () => {
      const session = createSession({
        lastInboundAt: now - 600000, // 10 min ago
      });
      const result = checkUnrespondedMessages({ enabled: false }, session);
      expect(result).toBeNull();
    });

    it("returns null when enabled is undefined", () => {
      const session = createSession({
        lastInboundAt: now - 600000,
      });
      const result = checkUnrespondedMessages({}, session);
      expect(result).toBeNull();
    });
  });

  describe("when no inbound messages", () => {
    it("returns null when lastInboundAt is undefined", () => {
      const session = createSession();
      const result = checkUnrespondedMessages({ enabled: true }, session);
      expect(result).toBeNull();
    });
  });

  describe("when outbound is newer than inbound", () => {
    it("returns null when lastOutboundAt > lastInboundAt", () => {
      const session = createSession({
        lastInboundAt: now - 600000, // 10 min ago
        lastOutboundAt: now - 300000, // 5 min ago (after inbound)
      });
      const result = checkUnrespondedMessages({ enabled: true }, session);
      expect(result).toBeNull();
    });

    it("returns null when lastOutboundAt equals lastInboundAt", () => {
      const session = createSession({
        lastInboundAt: now - 600000,
        lastOutboundAt: now - 600000,
      });
      const result = checkUnrespondedMessages({ enabled: true }, session);
      expect(result).toBeNull();
    });
  });

  describe("when inbound is newer and timeout exceeded", () => {
    it("returns result with default timeout (10m)", () => {
      const session = createSession({
        lastInboundAt: now - 600000, // 10 min ago
        lastOutboundAt: now - 900000, // 15 min ago (before inbound)
        lastInboundPreview: "Hello, help me!",
      });
      const result = checkUnrespondedMessages({ enabled: true }, session);

      expect(result).not.toBeNull();
      expect(result?.hasUnresponded).toBe(true);
      expect(result?.elapsedMs).toBe(600000);
      expect(result?.preview).toBe("Hello, help me!");
    });

    it("returns result with custom timeout (5m)", () => {
      const session = createSession({
        lastInboundAt: now - 300000, // 5 min ago
        lastOutboundAt: now - 600000, // 10 min ago
      });
      const result = checkUnrespondedMessages({ enabled: true, timeout: "5m" }, session);

      expect(result).not.toBeNull();
      expect(result?.hasUnresponded).toBe(true);
      expect(result?.elapsedMs).toBe(300000);
    });

    it("returns null when timeout not yet exceeded", () => {
      const session = createSession({
        lastInboundAt: now - 300000, // 5 min ago
        lastOutboundAt: now - 600000, // 10 min ago
      });
      const result = checkUnrespondedMessages({ enabled: true, timeout: "10m" }, session);

      expect(result).toBeNull();
    });

    it("uses default 10m timeout when not specified", () => {
      // Just under 10 minutes
      const session = createSession({
        lastInboundAt: now - 599999, // 9 min 59 sec ago
        lastOutboundAt: 0,
      });
      const result = checkUnrespondedMessages({ enabled: true }, session);
      expect(result).toBeNull();

      // Just over 10 minutes
      const session2 = createSession({
        lastInboundAt: now - 600001, // 10 min 1 sec ago
        lastOutboundAt: 0,
      });
      const result2 = checkUnrespondedMessages({ enabled: true }, session2);
      expect(result2).not.toBeNull();
    });
  });

  describe("preview handling", () => {
    it("includes preview in result when available", () => {
      const session = createSession({
        lastInboundAt: now - 600000,
        lastOutboundAt: 0,
        lastInboundPreview: "Can you check the logs?",
      });
      const result = checkUnrespondedMessages({ enabled: true }, session);

      expect(result?.preview).toBe("Can you check the logs?");
    });

    it("returns undefined preview when not available", () => {
      const session = createSession({
        lastInboundAt: now - 600000,
        lastOutboundAt: 0,
      });
      const result = checkUnrespondedMessages({ enabled: true }, session);

      expect(result?.preview).toBeUndefined();
    });
  });
});
