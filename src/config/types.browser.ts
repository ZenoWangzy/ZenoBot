/**
 * Browser connection mode.
 * - auto: Try CDP direct first, fallback to extension relay (default)
 * - cdp-direct: Only use CDP direct connection
 * - extension-relay: Only use Chrome extension relay
 */
export type BrowserConnectionMode = "auto" | "cdp-direct" | "extension-relay";

/**
 * CDP (Chrome DevTools Protocol) configuration.
 */
export type BrowserCdpConfig = {
  /** CDP port for debugging. Default: 9222 */
  port?: number;
  /** Auto-launch Chrome with CDP enabled if not running. Default: true */
  autoLaunch?: boolean;
  /** Directory for Chrome profile (persistent login state). Default: ~/.openclaw/browser-profiles/default */
  profileDir?: string;
};

/**
 * Connection watchdog configuration for auto-reconnect.
 */
export type BrowserWatchdogConfig = {
  /** Enable connection watchdog for auto-reconnect. Default: true */
  enabled?: boolean;
  /** Interval between connection checks (ms). Default: 5000 */
  checkInterval?: number;
  /** Max consecutive failures before restarting browser. Default: 3 */
  maxRetries?: number;
  /** Auto-restart browser after max failures. Default: true */
  autoRestart?: boolean;
};

/**
 * Timeout configuration for browser operations.
 */
export type BrowserTimeoutConfig = {
  /** Connection timeout (ms). Default: 60000 */
  connect?: number;
  /** Single operation timeout (ms). Default: 30000 */
  operation?: number;
  /** Idle timeout before disconnecting (ms). Default: 300000 (5 min) */
  idle?: number;
};

export type BrowserProfileConfig = {
  /** CDP port for this profile. Allocated once at creation, persisted permanently. */
  cdpPort?: number;
  /** CDP URL for this profile (use for remote Chrome). */
  cdpUrl?: string;
  /** Profile driver (default: openclaw). */
  driver?: "openclaw" | "extension";
  /** Profile color (hex). Auto-assigned at creation. */
  color: string;
};
export type BrowserSnapshotDefaults = {
  /** Default snapshot mode (applies when mode is not provided). */
  mode?: "efficient";
};
export type BrowserConfig = {
  enabled?: boolean;
  /** If false, disable browser act:evaluate (arbitrary JS). Default: true */
  evaluateEnabled?: boolean;
  /** Base URL of the CDP endpoint (for remote browsers). Default: loopback CDP on the derived port. */
  cdpUrl?: string;
  /** Remote CDP HTTP timeout (ms). Default: 1500. */
  remoteCdpTimeoutMs?: number;
  /** Remote CDP WebSocket handshake timeout (ms). Default: max(remoteCdpTimeoutMs * 2, 2000). */
  remoteCdpHandshakeTimeoutMs?: number;
  /** Accent color for the openclaw browser profile (hex). Default: #FF4500 */
  color?: string;
  /** Override the browser executable path (all platforms). */
  executablePath?: string;
  /** Start Chrome headless (best-effort). Default: false */
  headless?: boolean;
  /** Pass --no-sandbox to Chrome (Linux containers). Default: false */
  noSandbox?: boolean;
  /** If true: never launch; only attach to an existing browser. Default: false */
  attachOnly?: boolean;
  /** Default profile to use when profile param is omitted. Default: "chrome" */
  defaultProfile?: string;
  /** Named browser profiles with explicit CDP ports or URLs. */
  profiles?: Record<string, BrowserProfileConfig>;
  /** Default snapshot options (applied by the browser tool/CLI when unset). */
  snapshotDefaults?: BrowserSnapshotDefaults;
  /** Connection mode: auto (CDP first), cdp-direct, or extension-relay. Default: auto */
  mode?: BrowserConnectionMode;
  /** CDP (Chrome DevTools Protocol) configuration. */
  cdp?: BrowserCdpConfig;
  /** Connection watchdog configuration for auto-reconnect. */
  watchdog?: BrowserWatchdogConfig;
  /** Timeout configuration for browser operations. */
  timeouts?: BrowserTimeoutConfig;
};
