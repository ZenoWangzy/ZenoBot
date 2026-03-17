import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

describe("openclaw-fix.sh", () => {
  it("bypasses proxy when checking the local gateway health endpoint", () => {
    const scriptPath = path.join(process.cwd(), "scripts", "openclaw-fix.sh");
    const script = fs.readFileSync(scriptPath, "utf8");

    expect(script).toContain(
      'curl -sf --noproxy "*" --max-time 5 "http://127.0.0.1:${GATEWAY_PORT}/health"',
    );
  });

  it("reloads the LaunchAgent when the gateway service is missing instead of booting it out", () => {
    const scriptPath = path.join(process.cwd(), "scripts", "openclaw-fix.sh");
    const script = fs.readFileSync(scriptPath, "utf8");

    expect(script).toContain('launchctl bootstrap "gui/$UID" "$GATEWAY_PLIST"');
    expect(script).not.toContain("launchctl bootout gui/$UID/$GATEWAY_LABEL");
  });
});
