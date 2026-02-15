/**
 * Browser Launcher - Auto-detect and launch Chrome with CDP enabled.
 *
 * Provides automatic detection of existing Chrome instances with CDP enabled,
 * and launching new Chrome instances when needed.
 */

import { type ChildProcessWithoutNullStreams, spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createSubsystemLogger } from "../logging/subsystem.js";
import { CONFIG_DIR } from "../utils.js";
import { getHeadersWithAuth, normalizeCdpWsUrl } from "./cdp.js";
import {
  type BrowserExecutable,
  resolveBrowserExecutableForPlatform,
} from "./chrome.executables.js";
import type { ResolvedBrowserConfig } from "./config.js";
import { DEFAULT_OPENCLAW_BROWSER_PROFILE_NAME } from "./constants.js";
import type { BrowserCdpConfig } from "../config/types.browser.js";

const log = createSubsystemLogger("browser").child("launcher");

/** CDP information for a running Chrome instance. */
export type CDPInfo = {
  /** Whether CDP is reachable. */
  reachable: boolean;
  /** WebSocket debugger URL (if reachable). */
  webSocketDebuggerUrl?: string;
  /** Browser version string. */
  browserVersion?: string;
  /** User agent string. */
  userAgent?: string;
  /** CDP port. */
  port: number;
};

/** A running Chrome process managed by the launcher. */
export type ChromeProcess = {
  /** Process handle. */
  proc: ChildProcessWithoutNullStreams;
  /** PID of the process. */
  pid: number;
  /** CDP port. */
  cdpPort: number;
  /** User data directory. */
  userDataDir: string;
  /** Executable info. */
  executable: BrowserExecutable;
  /** Timestamp when started. */
  startedAt: number;
};

/** Default CDP port. */
export const DEFAULT_CDP_PORT = 9222;

/** Default profile directory. */
export const DEFAULT_PROFILE_DIR = () =>
  path.join(CONFIG_DIR, "browser", DEFAULT_OPENCLAW_BROWSER_PROFILE_NAME, "user-data");

/**
 * Detect if Chrome is already running with CDP enabled at the specified port.
 */
export async function detectExistingCDP(port = DEFAULT_CDP_PORT): Promise<CDPInfo> {
  const cdpUrl = `http://127.0.0.1:${port}`;
  const info: CDPInfo = {
    reachable: false,
    port,
  };

  try {
    const versionUrl = `${cdpUrl}/json/version`;
    const ctrl = new AbortController();
    const timeout = setTimeout(ctrl.abort.bind(ctrl), 1500);

    const res = await fetch(versionUrl, {
      signal: ctrl.signal,
      headers: getHeadersWithAuth(versionUrl),
    });
    clearTimeout(timeout);

    if (!res.ok) {
      return info;
    }

    const data = (await res.json()) as {
      webSocketDebuggerUrl?: string;
      Browser?: string;
      "User-Agent"?: string;
    };

    if (data && typeof data === "object") {
      info.reachable = true;
      info.browserVersion = data.Browser;
      info.userAgent = data["User-Agent"];

      if (data.webSocketDebuggerUrl) {
        info.webSocketDebuggerUrl = normalizeCdpWsUrl(data.webSocketDebuggerUrl, cdpUrl);
      }
    }
  } catch {
    // Chrome not reachable at this port
  }

  return info;
}

/**
 * Find Chrome executable on the system.
 * Returns the first supported browser found.
 */
export function findChromeExecutable(
  config?: ResolvedBrowserConfig,
): BrowserExecutable | null {
  return resolveBrowserExecutableForPlatform(
    config ?? ({} as ResolvedBrowserConfig),
    process.platform,
  );
}

/**
 * Launch Chrome with CDP enabled.
 */
export async function launchWithCDP(options: {
  port?: number;
  profileDir?: string;
  startingUrl?: string;
  headless?: boolean;
  noSandbox?: boolean;
  config?: ResolvedBrowserConfig;
}): Promise<ChromeProcess> {
  const {
    port = DEFAULT_CDP_PORT,
    profileDir = DEFAULT_PROFILE_DIR(),
    startingUrl = "about:blank",
    headless = false,
    noSandbox = false,
    config,
  } = options;

  const exe = findChromeExecutable(config);
  if (!exe) {
    throw new Error(
      "No supported browser found (Chrome/Brave/Edge/Chromium on macOS, Linux, or Windows).",
    );
  }

  // Ensure profile directory exists
  fs.mkdirSync(profileDir, { recursive: true });

  const args: string[] = [
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${profileDir}`,
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-sync",
    "--disable-background-networking",
    "--disable-component-update",
    "--disable-features=Translate,MediaRouter",
    "--disable-session-crashed-bubble",
    "--hide-crash-restore-bubble",
    "--password-store=basic",
    // Stealth: hide navigator.webdriver from automation detection
    "--disable-blink-features=AutomationControlled",
    startingUrl,
  ];

  if (headless) {
    args.push("--headless=new");
    args.push("--disable-gpu");
  }

  if (noSandbox) {
    args.push("--no-sandbox");
    args.push("--disable-setuid-sandbox");
  }

  if (process.platform === "linux") {
    args.push("--disable-dev-shm-usage");
  }

  log.info(`Launching ${exe.kind} with CDP on port ${port}`);

  const proc = spawn(exe.path, args, {
    stdio: "pipe",
    env: {
      ...process.env,
      HOME: os.homedir(),
    },
  });

  const startedAt = Date.now();

  // Wait for Chrome to be ready
  const deadline = Date.now() + 30000; // 30 seconds timeout
  while (Date.now() < deadline) {
    const info = await detectExistingCDP(port);
    if (info.reachable) {
      log.info(`Chrome ready on port ${port}`);
      break;
    }
    if (proc.exitCode !== null) {
      throw new Error(`Chrome exited unexpectedly with code ${proc.exitCode}`);
    }
    await new Promise((r) => setTimeout(r, 200));
  }

  if (proc.exitCode === null) {
    const info = await detectExistingCDP(port);
    if (!info.reachable) {
      proc.kill("SIGTERM");
      throw new Error("Chrome failed to start within timeout");
    }
  }

  return {
    proc,
    pid: proc.pid!,
    cdpPort: port,
    userDataDir: profileDir,
    executable: exe,
    startedAt,
  };
}

/**
 * Get the resolved CDP config with defaults applied.
 */
export function resolveCdpConfig(config?: BrowserCdpConfig): Required<BrowserCdpConfig> {
  return {
    port: config?.port ?? DEFAULT_CDP_PORT,
    autoLaunch: config?.autoLaunch ?? true,
    profileDir: config?.profileDir ?? DEFAULT_PROFILE_DIR(),
  };
}

/**
 * Gracefully terminate a Chrome process.
 */
export async function terminateChrome(process: ChromeProcess, timeout = 5000): Promise<void> {
  if (process.proc.exitCode !== null) {
    return;
  }

  // Try graceful shutdown first
  process.proc.kill("SIGTERM");

  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (process.proc.exitCode !== null) {
      return;
    }
    await new Promise((r) => setTimeout(r, 100));
  }

  // Force kill if still running
  if (process.proc.exitCode === null) {
    log.warn(`Chrome did not exit gracefully, force killing PID ${process.pid}`);
    process.proc.kill("SIGKILL");
  }
}
