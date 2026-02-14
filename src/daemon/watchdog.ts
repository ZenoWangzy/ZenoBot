import net from "node:net";
import path from "node:path";

/**
 * Check if a port is being listened on (Windows only).
 * On non-Windows platforms, always returns true (no-op).
 */
export async function isPortListening(port: number, host = "127.0.0.1"): Promise<boolean> {
  if (process.platform !== "win32") {
    return true;
  }

  return new Promise((resolve) => {
    const socket = new net.Socket();
    const timeout = 5000;

    const onError = () => {
      socket.destroy();
      resolve(false);
    };

    socket.setTimeout(timeout);
    socket.once("error", onError);
    socket.once("timeout", onError);

    socket.connect(port, host, () => {
      socket.end();
      resolve(true);
    });
  });
}

/**
 * Resolve the watchdog script path for Windows Scheduled Task.
 */
export function resolveWatchdogScriptPath(env: Record<string, string | undefined>): string {
  const stateDir = env.OPENCLAW_STATE_DIR?.trim();
  if (stateDir) {
    const home = stateDir.startsWith("~") ? env.HOME?.trim() || env.USERPROFILE?.trim() : undefined;
    const basePath = home ? stateDir.replace(/^~(?=$|[/\\])/, home) : stateDir;
    return path.join(basePath, "gateway-watchdog.cmd");
  }

  const home = env.HOME?.trim() || env.USERPROFILE?.trim();
  if (!home) {
    throw new Error("Missing HOME or USERPROFILE");
  }

  const profile = env.OPENCLAW_PROFILE?.trim();
  const suffix = profile && profile.toLowerCase() !== "default" ? `-${profile}` : "";
  return path.join(home, `.openclaw${suffix}`, "gateway-watchdog.cmd");
}

/**
 * Quote a command argument for Windows batch script if needed.
 */
function quoteCmdArg(value: string): string {
  if (!/[ \t"]/g.test(value)) {
    return value;
  }
  return `"${value.replace(/"/g, '\\"')}"`;
}

export type WatchdogScriptParams = {
  programArguments: string[];
  workingDirectory?: string;
  environment?: Record<string, string | undefined>;
};

/**
 * Build a Windows batch script that checks port and starts gateway if not running.
 */
export function buildWatchdogScript(params: WatchdogScriptParams): string {
  const lines: string[] = ["@echo off"];
  lines.push("rem OpenClaw Gateway Watchdog");

  // Change to working directory
  if (params.workingDirectory) {
    lines.push(`cd /d ${quoteCmdArg(params.workingDirectory)}`);
  }

  // Set environment variables
  if (params.environment) {
    for (const [key, value] of Object.entries(params.environment)) {
      if (value) {
        lines.push(`set ${key}=${value}`);
      }
    }
  }

  // Check if gateway is already running via port check
  // Use netstat to check if port is listening
  const port = params.programArguments.includes("--port")
    ? params.programArguments[params.programArguments.indexOf("--port") + 1]
    : "18789";

  lines.push("");
  lines.push("rem Check if gateway port is already listening");
  lines.push(`netstat -an | findstr ":${port}.*LISTENING" >nul 2>&1`);
  lines.push("if %errorlevel% equ 0 (");
  lines.push("    rem Gateway already running, exit silently");
  lines.push("    exit /b 0");
  lines.push(")");

  // Start gateway
  lines.push("");
  lines.push("rem Gateway not running, start it");
  const command = params.programArguments.map(quoteCmdArg).join(" ");
  lines.push(`start /b "" ${command}`);

  return `${lines.join("\r\n")}\r\n`;
}
