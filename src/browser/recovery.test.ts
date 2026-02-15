import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import {
  SessionStateRecovery,
  createSessionStateRecovery,
  DEFAULT_TIMEOUT_CONFIG,
  type SessionSnapshot,
} from "./recovery.js";

describe("recovery", () => {
  describe("DEFAULT_TIMEOUT_CONFIG", () => {
    it("has expected defaults", () => {
      expect(DEFAULT_TIMEOUT_CONFIG.connect).toBe(60000);
      expect(DEFAULT_TIMEOUT_CONFIG.operation).toBe(30000);
      expect(DEFAULT_TIMEOUT_CONFIG.idle).toBe(300000);
    });
  });

  describe("SessionStateRecovery", () => {
    let recovery: SessionStateRecovery;

    beforeEach(() => {
      recovery = new SessionStateRecovery();
      vi.useFakeTimers();
    });

    afterEach(() => {
      vi.useRealTimers();
    });

    it("creates with default options", () => {
      const options = recovery.getOptions();
      expect(options.maxSnapshotAge).toBe(60000);
      expect(options.restoreScrollPosition).toBe(true);
      expect(options.restoreFormData).toBe(true);
    });

    it("merges custom options", () => {
      const customRecovery = new SessionStateRecovery({
        maxSnapshotAge: 120000,
        restoreScrollPosition: false,
      });
      const options = customRecovery.getOptions();

      expect(options.maxSnapshotAge).toBe(120000);
      expect(options.restoreScrollPosition).toBe(false);
      expect(options.restoreFormData).toBe(true); // default
    });

    it("saves and retrieves snapshot", () => {
      const snapshot: SessionSnapshot = {
        activeTabUrl: "https://example.com/page",
        activeTabTitle: "Example Page",
        scrollPosition: { x: 0, y: 500 },
        formData: { username: "test" },
        timestamp: Date.now(),
      };

      recovery.saveSnapshot(snapshot);
      const retrieved = recovery.getSnapshot();

      expect(retrieved).not.toBeNull();
      expect(retrieved?.activeTabUrl).toBe(snapshot.activeTabUrl);
      expect(retrieved?.activeTabTitle).toBe(snapshot.activeTabTitle);
      expect(retrieved?.scrollPosition).toEqual(snapshot.scrollPosition);
      expect(retrieved?.formData).toEqual(snapshot.formData);
    });

    it("clears snapshot", () => {
      const snapshot: SessionSnapshot = {
        activeTabUrl: "https://example.com",
        activeTabTitle: "Example",
        scrollPosition: { x: 0, y: 0 },
        formData: {},
        timestamp: Date.now(),
      };

      recovery.saveSnapshot(snapshot);
      expect(recovery.getSnapshot()).not.toBeNull();

      recovery.clearSnapshot();
      expect(recovery.getSnapshot()).toBeNull();
    });

    it("validates snapshot age", () => {
      const snapshot: SessionSnapshot = {
        activeTabUrl: "https://example.com",
        activeTabTitle: "Example",
        scrollPosition: { x: 0, y: 0 },
        formData: {},
        timestamp: Date.now(),
      };

      recovery.saveSnapshot(snapshot);
      expect(recovery.isSnapshotValid()).toBe(true);

      // Advance time past max age
      vi.advanceTimersByTime(61000);
      expect(recovery.isSnapshotValid()).toBe(false);
    });

    it("returns null for stale snapshot in getRecoveryData", () => {
      const snapshot: SessionSnapshot = {
        activeTabUrl: "https://example.com",
        activeTabTitle: "Example",
        scrollPosition: { x: 0, y: 0 },
        formData: {},
        timestamp: Date.now(),
      };

      recovery.saveSnapshot(snapshot);

      // Advance time past max age
      vi.advanceTimersByTime(61000);

      expect(recovery.getRecoveryData()).toBeNull();
    });

    it("returns snapshot for valid snapshot in getRecoveryData", () => {
      const snapshot: SessionSnapshot = {
        activeTabUrl: "https://example.com",
        activeTabTitle: "Example",
        scrollPosition: { x: 0, y: 0 },
        formData: {},
        timestamp: Date.now(),
      };

      recovery.saveSnapshot(snapshot);
      expect(recovery.getRecoveryData()).not.toBeNull();
    });

    it("updates options dynamically", () => {
      recovery.updateOptions({ maxSnapshotAge: 30000 });
      const options = recovery.getOptions();

      expect(options.maxSnapshotAge).toBe(30000);
    });

    describe("static methods", () => {
      it("creates snapshot from page state", () => {
        const pageState = {
          url: "https://example.com",
          title: "Example",
          scrollX: 100,
          scrollY: 200,
          formData: { field1: "value1" },
        };

        const snapshot = SessionStateRecovery.createSnapshotFromPageState(pageState);

        expect(snapshot.activeTabUrl).toBe(pageState.url);
        expect(snapshot.activeTabTitle).toBe(pageState.title);
        expect(snapshot.scrollPosition.x).toBe(pageState.scrollX);
        expect(snapshot.scrollPosition.y).toBe(pageState.scrollY);
        expect(snapshot.formData).toEqual(pageState.formData);
        expect(snapshot.timestamp).toBeGreaterThan(0);
      });

      it("generates page state script", () => {
        const script = SessionStateRecovery.getPageStateScript();

        expect(script).toContain("window.location.href");
        expect(script).toContain("document.title");
        expect(script).toContain("window.scrollX");
        expect(script).toContain("window.scrollY");
      });

      it("generates restore state script", () => {
        const snapshot: SessionSnapshot = {
          activeTabUrl: "https://example.com",
          activeTabTitle: "Example",
          scrollPosition: { x: 100, y: 200 },
          formData: { field1: "value1" },
          timestamp: Date.now(),
        };

        const script = SessionStateRecovery.getRestoreStateScript(snapshot);

        expect(script).toContain("window.scrollTo(100, 200)");
        expect(script).toContain("field1");
        expect(script).toContain("value1");
      });

      it("generates restore script without form data", () => {
        const snapshot: SessionSnapshot = {
          activeTabUrl: "https://example.com",
          activeTabTitle: "Example",
          scrollPosition: { x: 0, y: 0 },
          formData: {},
          timestamp: Date.now(),
        };

        const script = SessionStateRecovery.getRestoreStateScript(snapshot);

        expect(script).toContain("window.scrollTo(0, 0)");
        // Should not have formData assignment when empty
        expect(script).not.toContain("const formData = {}");
      });
    });
  });

  describe("createSessionStateRecovery", () => {
    it("creates a recovery instance", () => {
      const recovery = createSessionStateRecovery();
      expect(recovery).toBeInstanceOf(SessionStateRecovery);
    });

    it("passes options to instance", () => {
      const recovery = createSessionStateRecovery({ maxSnapshotAge: 5000 });
      const options = recovery.getOptions();
      expect(options.maxSnapshotAge).toBe(5000);
    });
  });
});
