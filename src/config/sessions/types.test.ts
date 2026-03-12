import { describe, expect, it } from "vitest";
import type { SessionEntry } from "./types.js";

describe("SessionEntry timestamps", () => {
  it("should accept lastInboundAt timestamp", () => {
    const entry: SessionEntry = {
      sessionId: "test",
      updatedAt: Date.now(),
      lastInboundAt: Date.now(),
    };
    expect(entry.lastInboundAt).toBeDefined();
  });

  it("should accept lastOutboundAt timestamp", () => {
    const entry: SessionEntry = {
      sessionId: "test",
      updatedAt: Date.now(),
      lastOutboundAt: Date.now(),
    };
    expect(entry.lastOutboundAt).toBeDefined();
  });

  it("should accept lastInboundPreview string", () => {
    const entry: SessionEntry = {
      sessionId: "test",
      updatedAt: Date.now(),
      lastInboundPreview: "Hello, can you help me?",
    };
    expect(entry.lastInboundPreview).toBe("Hello, can you help me?");
  });
});
