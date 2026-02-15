/**
 * Session State Recovery - Save and restore browser session state.
 *
 * Provides functionality to capture browser state snapshots
 * and restore them after reconnection.
 */

import { createSubsystemLogger } from "../logging/subsystem.js";

const log = createSubsystemLogger("browser").child("recovery");

/** Session state snapshot for recovery. */
export interface SessionSnapshot {
  /** Active tab URL. */
  activeTabUrl: string;
  /** Active tab title. */
  activeTabTitle: string;
  /** Scroll position. */
  scrollPosition: { x: number; y: number };
  /** Form data (field name -> value). */
  formData: Record<string, string>;
  /** Timestamp when snapshot was taken. */
  timestamp: number;
}

/** Options for state recovery. */
export interface RecoveryOptions {
  /** Maximum age of snapshot before it's considered stale (ms). Default: 60000 */
  maxSnapshotAge?: number;
  /** Whether to restore scroll position. Default: true */
  restoreScrollPosition?: boolean;
  /** Whether to restore form data. Default: true */
  restoreFormData?: boolean;
}

const DEFAULT_OPTIONS: Required<RecoveryOptions> = {
  maxSnapshotAge: 60000, // 1 minute
  restoreScrollPosition: true,
  restoreFormData: true,
};

/**
 * Session State Recovery manager.
 *
 * Captures and restores browser session state for recovery scenarios.
 */
export class SessionStateRecovery {
  private snapshot: SessionSnapshot | null = null;
  private options: Required<RecoveryOptions>;

  constructor(options?: RecoveryOptions) {
    this.options = { ...DEFAULT_OPTIONS, ...options };
  }

  /**
   * Save a session state snapshot.
   */
  saveSnapshot(snapshot: SessionSnapshot): void {
    this.snapshot = {
      ...snapshot,
      timestamp: Date.now(),
    };
    log.info(
      `Snapshot saved: ${snapshot.activeTabUrl.substring(0, 50)}...`
    );
  }

  /**
   * Get the current snapshot.
   */
  getSnapshot(): SessionSnapshot | null {
    return this.snapshot;
  }

  /**
   * Check if the snapshot is still valid (not too old).
   */
  isSnapshotValid(): boolean {
    if (!this.snapshot) {
      return false;
    }
    const age = Date.now() - this.snapshot.timestamp;
    return age < this.options.maxSnapshotAge;
  }

  /**
   * Clear the current snapshot.
   */
  clearSnapshot(): void {
    this.snapshot = null;
    log.info("Snapshot cleared");
  }

  /**
   * Get recovery data for a page.
   * Returns null if no valid snapshot exists.
   */
  getRecoveryData(): SessionSnapshot | null {
    if (!this.isSnapshotValid()) {
      log.warn("Snapshot is stale or missing");
      return null;
    }
    return this.snapshot;
  }

  /**
   * Create a snapshot from page evaluation result.
   */
  static createSnapshotFromPageState(
    pageState: {
      url: string;
      title: string;
      scrollX: number;
      scrollY: number;
      formData: Record<string, string>;
    }
  ): SessionSnapshot {
    return {
      activeTabUrl: pageState.url,
      activeTabTitle: pageState.title,
      scrollPosition: { x: pageState.scrollX, y: pageState.scrollY },
      formData: pageState.formData,
      timestamp: Date.now(),
    };
  }

  /**
   * Generate JavaScript to capture page state.
   * Run this in the browser context to get the current state.
   */
  static getPageStateScript(): string {
    return `
      (function() {
        const formData = {};
        document.querySelectorAll('input, textarea, select').forEach(el => {
          const name = el.name || el.id;
          if (name && el.type !== 'password') {
            formData[name] = el.value;
          }
        });
        return {
          url: window.location.href,
          title: document.title,
          scrollX: window.scrollX,
          scrollY: window.scrollY,
          formData: formData
        };
      })()
    `;
  }

  /**
   * Generate JavaScript to restore page state.
   */
  static getRestoreStateScript(snapshot: SessionSnapshot): string {
    const scrollScript = `window.scrollTo(${snapshot.scrollPosition.x}, ${snapshot.scrollPosition.y});`;

    let formScript = "";
    if (Object.keys(snapshot.formData).length > 0) {
      const formDataJson = JSON.stringify(snapshot.formData);
      formScript = `
        const formData = ${formDataJson};
        Object.entries(formData).forEach(([name, value]) => {
          const el = document.querySelector('[name="' + name + '"], #' + name);
          if (el && el.type !== 'password') {
            el.value = value;
          }
        });
      `;
    }

    return `(function() { ${scrollScript} ${formScript} })()`;
  }

  /**
   * Update recovery options.
   */
  updateOptions(options: Partial<RecoveryOptions>): void {
    this.options = { ...this.options, ...options };
  }

  /**
   * Get current options.
   */
  getOptions(): Required<RecoveryOptions> {
    return { ...this.options };
  }
}

/**
 * Create a session state recovery instance.
 */
export function createSessionStateRecovery(
  options?: RecoveryOptions,
): SessionStateRecovery {
  return new SessionStateRecovery(options);
}

/**
 * Default timeout configuration for browser operations.
 */
export const DEFAULT_TIMEOUT_CONFIG = {
  /** Connection timeout (ms). */
  connect: 60000,
  /** Single operation timeout (ms). */
  operation: 30000,
  /** Idle timeout before disconnecting (ms). */
  idle: 300000, // 5 minutes
};
