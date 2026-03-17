import { describe, expect, it } from "vitest";
import type { AgentDefaultsConfig } from "./types.agent-defaults.js";

describe("AgentDefaultsConfig heartbeat.unresponded", () => {
  it("should accept unresponded config", () => {
    const config: AgentDefaultsConfig = {
      heartbeat: {
        every: "5m",
        unresponded: {
          enabled: true,
          timeout: "10m",
        },
      },
    };
    expect(config.heartbeat?.unresponded?.enabled).toBe(true);
  });
});
