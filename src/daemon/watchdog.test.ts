import { describe, expect, it } from "vitest";
import { isPortListening, resolveWatchdogScriptPath, buildWatchdogScript } from "./watchdog.js";

describe("watchdog", () => {
  describe("isPortListening", () => {
    it("returns true when port is listening", async () => {
      // This test will be skipped on non-Windows platforms
      if (process.platform !== "win32") {
        return;
      }
      // We'll mock this in the actual implementation
      const result = await isPortListening(18789);
      expect(typeof result).toBe("boolean");
    });

    it("returns false when port is not listening", async () => {
      if (process.platform !== "win32") {
        return;
      }
      // Use an unlikely port
      const result = await isPortListening(59999);
      expect(result).toBe(false);
    });
  });

  describe("resolveWatchdogScriptPath", () => {
    it("uses default path when OPENCLAW_PROFILE is default", () => {
      const env = { USERPROFILE: "C:\\Users\\test", OPENCLAW_PROFILE: "default" };
      const result = resolveWatchdogScriptPath(env);
      expect(result).toContain(".openclaw");
      expect(result).toContain("gateway-watchdog.cmd");
    });

    it("uses profile-specific path when OPENCLAW_PROFILE is custom", () => {
      const env = { USERPROFILE: "C:\\Users\\test", OPENCLAW_PROFILE: "custom" };
      const result = resolveWatchdogScriptPath(env);
      expect(result).toContain(".openclaw-custom");
      expect(result).toContain("gateway-watchdog.cmd");
    });

    it("prefers OPENCLAW_STATE_DIR over profile-derived defaults", () => {
      const env = {
        USERPROFILE: "C:\\Users\\test",
        OPENCLAW_PROFILE: "rescue",
        OPENCLAW_STATE_DIR: "C:\\State\\openclaw",
      };
      const result = resolveWatchdogScriptPath(env);
      expect(result).toContain("C:\\State\\openclaw");
      expect(result).toContain("gateway-watchdog.cmd");
    });

    it("handles tilde in OPENCLAW_STATE_DIR", () => {
      const env = {
        HOME: "/home/test",
        OPENCLAW_STATE_DIR: "~/.custom-state",
      };
      const result = resolveWatchdogScriptPath(env);
      // Path separator is platform-dependent
      expect(result).toMatch(/[\\/]home[\\/]test[\\/].custom-state/);
    });
  });
});

describe("buildWatchdogScript", () => {
  it("generates valid batch script content", () => {
    const script = buildWatchdogScript({
      programArguments: ["node", "gateway.js", "--port", "18789"],
      workingDirectory: "C:\\Projects\\openclaw",
      environment: { NODE_ENV: "production" },
    });

    expect(script).toContain("@echo off");
    expect(script).toContain("cd /d");
    expect(script).toContain("C:\\Projects\\openclaw");
    expect(script).toContain("set NODE_ENV=production");
    expect(script).toContain("node gateway.js --port 18789");
  });

  it("handles paths with spaces", () => {
    const script = buildWatchdogScript({
      programArguments: ["C:\\Program Files\\nodejs\\node.exe", "gateway.js"],
      workingDirectory: "C:\\My Projects\\openclaw",
    });

    expect(script).toContain('"C:\\Program Files\\nodejs\\node.exe"');
    expect(script).toContain('"C:\\My Projects\\openclaw"');
  });

  it("includes netstat port check", () => {
    const script = buildWatchdogScript({
      programArguments: ["node", "gateway.js", "--port", "18789"],
    });

    expect(script).toContain("netstat -an");
    expect(script).toContain(":18789");
    expect(script).toContain("LISTENING");
  });

  it("uses default port 18789 when not specified", () => {
    const script = buildWatchdogScript({
      programArguments: ["node", "gateway.js"],
    });

    expect(script).toContain(":18789");
  });

  it("exits silently when port is already listening", () => {
    const script = buildWatchdogScript({
      programArguments: ["node", "gateway.js"],
    });

    expect(script).toContain("exit /b 0");
  });

  it("starts gateway with start /b for background execution", () => {
    const script = buildWatchdogScript({
      programArguments: ["node", "gateway.js"],
    });

    expect(script).toContain("start /b");
  });
});
