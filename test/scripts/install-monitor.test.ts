import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

describe("install-monitor.sh", () => {
  let tempDir: string;
  let fakeBinDir: string;
  let homeDir: string;

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-install-monitor-"));
    fakeBinDir = path.join(tempDir, "bin");
    homeDir = path.join(tempDir, "home");
    fs.mkdirSync(fakeBinDir, { recursive: true });
    fs.mkdirSync(path.join(homeDir, "Library", "LaunchAgents"), { recursive: true });
    fs.writeFileSync(path.join(fakeBinDir, "launchctl"), "#!/bin/sh\nexit 0\n", "utf8");
    fs.chmodSync(path.join(fakeBinDir, "launchctl"), 0o755);
  });

  afterEach(() => {
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  it("installs monitor scripts into a stable home path and points LaunchAgent at that copy", () => {
    execFileSync("bash", ["scripts/install-monitor.sh", "install"], {
      cwd: process.cwd(),
      env: {
        ...process.env,
        HOME: homeDir,
        PATH: `${fakeBinDir}:${process.env.PATH ?? ""}`,
      },
      stdio: "pipe",
    });

    const installedHealthScript = path.join(
      homeDir,
      ".openclaw",
      "scripts",
      "openclaw-health-check.sh",
    );
    const installedFixScript = path.join(homeDir, ".openclaw", "scripts", "openclaw-fix.sh");
    const plistPath = path.join(homeDir, "Library", "LaunchAgents", "ai.openclaw.monitor.plist");
    const plist = fs.readFileSync(plistPath, "utf8");

    expect(fs.existsSync(installedHealthScript)).toBe(true);
    expect(fs.existsSync(installedFixScript)).toBe(true);
    expect(plist).toContain(`<string>${installedHealthScript}</string>`);
    expect(plist).not.toContain(`${process.cwd()}/scripts/openclaw-health-check.sh`);
  });
});
