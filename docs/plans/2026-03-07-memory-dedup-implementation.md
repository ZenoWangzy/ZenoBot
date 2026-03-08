# Memory Dedup Detection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add similarity-based duplicate detection to memory_store, automatically skipping near-duplicate entries.

**Architecture:** Extend MemoryStore with checkDuplicate method that reuses existing embedding infrastructure. Synchronous check before storage, fail-open error handling, configurable threshold and scope mode.

**Tech Stack:** TypeScript, LanceDB (vector search), Node.js test runner

**Target Repo:** https://github.com/win4r/memory-lancedb-pro (Issue #30)

---

## Prerequisites

```bash
# Fork and clone the repo
gh repo fork win4r/memory-lancedb-pro --clone
cd memory-lancedb-pro
pnpm install
```

---

## Task 1: Extend Type Definitions

**Files:**

- Modify: `src/store.ts:37-50` (StoreConfig interface)

**Step 1: Add DedupConfig interface**

After the existing `StoreConfig` interface (around line 50), add:

```typescript
// ============================================================================
// Deduplication Types
// ============================================================================

export interface DedupConfig {
  /** Enable duplicate detection (default: true) */
  enabled?: boolean;
  /** Similarity threshold 0-1 (default: 0.92) */
  threshold?: number;
  /** Dedup scope: 'scope' = current scope only, 'global' = all scopes (default: 'scope') */
  scopeMode?: "scope" | "global";
}

export const DEFAULT_DEDUP_CONFIG: Required<DedupConfig> = {
  enabled: true,
  threshold: 0.92,
  scopeMode: "scope",
};
```

**Step 2: Extend StoreConfig interface**

Modify the StoreConfig interface to include dedup:

```typescript
export interface StoreConfig {
  dbPath: string;
  vectorDim: number;
  // Add this line:
  dedup?: DedupConfig;
}
```

**Step 3: Extend StoreParams interface**

Find the StoreParams interface and add the `force` parameter:

```typescript
export interface StoreParams {
  text: string;
  category?: MemoryEntry["category"];
  scope?: string;
  importance?: number;
  metadata?: Record<string, unknown>;
  // Add this line:
  force?: boolean; // Force store even if duplicate detected
}
```

**Step 4: Extend StoreResult interface**

Find the StoreResult interface and extend it:

```typescript
export interface StoreResult {
  id: string;
  status: "stored" | "skipped";
  // Add these fields:
  reason?: "duplicate";
  similarity?: number;
  similarTo?: {
    id: string;
    text: string;
    timestamp: number;
    scope: string;
  };
}
```

**Step 5: Commit types**

```bash
git add src/store.ts
git commit -m "feat(store): add dedup type definitions"
```

---

## Task 2: Write Dedup Tests

**Files:**

- Create: `test/dedup-detection.test.mjs`

**Step 1: Create test file with core tests**

```javascript
/**
 * Dedup Detection Tests
 * Issue: https://github.com/win4r/memory-lancedb-pro/issues/30
 */

import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mkdirSync, rmSync } from "node:fs";

const jitiFactory = (await import("jiti")).default;
const jiti = jitiFactory(import.meta.url, { interopDefault: true });
const { MemoryStore, DEFAULT_DEDUP_CONFIG } = jiti("../src/store.ts");

// ============================================================================
// Test Helpers
// ============================================================================

function createTestStore(dedupConfig = {}) {
  const testDir = join(tmpdir(), `dedup-test-${randomUUID()}`);
  mkdirSync(testDir, { recursive: true });

  return new MemoryStore({
    dbPath: testDir,
    vectorDim: 1024,
    dedup: { ...DEFAULT_DEDUP_CONFIG, ...dedupConfig },
  });
}

async function cleanup(store) {
  // Cleanup handled by store if available
}

// ============================================================================
// Tests
// ============================================================================

async function test_identical_text_detected_as_duplicate() {
  console.log("TEST: identical text detected as duplicate");
  const store = await createTestStore();

  // Store first memory
  const r1 = await store.memory_store({
    text: "OpenClaw supports Discord and Telegram channels",
    scope: "test",
  });
  assert.strictEqual(r1.status, "stored", "First store should succeed");

  // Attempt to store identical text
  const r2 = await store.memory_store({
    text: "OpenClaw supports Discord and Telegram channels",
    scope: "test",
  });
  assert.strictEqual(r2.status, "skipped", "Second store should be skipped");
  assert.strictEqual(r2.reason, "duplicate", "Reason should be duplicate");
  assert.ok(r2.similarity >= 0.99, `Similarity should be >= 0.99, got ${r2.similarity}`);
  assert.ok(r2.similarTo, "Should have similarTo info");
  assert.strictEqual(r2.similarTo.scope, "test", "Should show matching scope");

  console.log("  ✅ PASS");
  await cleanup(store);
}

async function test_similar_text_detected() {
  console.log("TEST: similar text (>92%) detected");
  const store = await createTestStore();

  await store.memory_store({
    text: "Redis is used for session caching in production",
    scope: "test",
  });

  const r = await store.memory_store({
    text: "Redis is used for caching sessions in production",
    scope: "test",
  });

  assert.strictEqual(r.status, "skipped", "Similar text should be skipped");
  assert.ok(r.similarity >= 0.92, `Similarity should be >= 0.92, got ${r.similarity}`);

  console.log("  ✅ PASS");
  await cleanup(store);
}

async function test_different_text_stored_normally() {
  console.log("TEST: different text stored normally");
  const store = await createTestStore();

  await store.memory_store({
    text: "Python is a programming language",
    scope: "test",
  });

  const r = await store.memory_store({
    text: "TypeScript adds static typing to JavaScript",
    scope: "test",
  });

  assert.strictEqual(r.status, "stored", "Different text should be stored");
  assert.strictEqual(r.reason, undefined, "Should not have reason");

  console.log("  ✅ PASS");
  await cleanup(store);
}

async function test_force_bypasses_dedup() {
  console.log("TEST: force:true bypasses dedup");
  const store = await createTestStore();

  await store.memory_store({
    text: "Important config: API key is abc123",
    scope: "test",
  });

  const r = await store.memory_store({
    text: "Important config: API key is abc123",
    scope: "test",
    force: true,
  });

  assert.strictEqual(r.status, "stored", "Force should store duplicate");

  console.log("  ✅ PASS");
  await cleanup(store);
}

async function test_scope_isolation() {
  console.log("TEST: scope isolation - different scopes allow duplicates");
  const store = await createTestStore({ scopeMode: "scope" });

  await store.memory_store({
    text: "User prefers dark mode",
    scope: "user:alice",
  });

  const r = await store.memory_store({
    text: "User prefers dark mode",
    scope: "user:bob",
  });

  // Different scope = should be stored
  assert.strictEqual(r.status, "stored", "Different scope should allow duplicate");

  console.log("  ✅ PASS");
  await cleanup(store);
}

async function test_global_mode_cross_scope() {
  console.log("TEST: global mode - cross-scope dedup");
  const store = await createTestStore({ scopeMode: "global" });

  await store.memory_store({
    text: "Shared configuration value",
    scope: "project:x",
  });

  const r = await store.memory_store({
    text: "Shared configuration value",
    scope: "project:y",
  });

  assert.strictEqual(r.status, "skipped", "Global mode should dedup across scopes");

  console.log("  ✅ PASS");
  await cleanup(store);
}

async function test_disabled_dedup() {
  console.log("TEST: dedup.enabled=false disables dedup");
  const store = await createTestStore({ enabled: false });

  await store.memory_store({
    text: "Duplicate content test",
    scope: "test",
  });

  const r = await store.memory_store({
    text: "Duplicate content test",
    scope: "test",
  });

  assert.strictEqual(r.status, "stored", "Disabled dedup should store all");

  console.log("  ✅ PASS");
  await cleanup(store);
}

// ============================================================================
// Runner
// ============================================================================

async function run() {
  console.log("\n=== Dedup Detection Tests ===\n");

  const tests = [
    test_identical_text_detected_as_duplicate,
    test_similar_text_detected,
    test_different_text_stored_normally,
    test_force_bypasses_dedup,
    test_scope_isolation,
    test_global_mode_cross_scope,
    test_disabled_dedup,
  ];

  let passed = 0;
  let failed = 0;

  for (const test of tests) {
    try {
      await test();
      passed++;
    } catch (err) {
      console.log(`  ❌ FAIL: ${err.message}`);
      failed++;
    }
  }

  console.log(`\n=== Results: ${passed}/${tests.length} passed ===\n`);
  process.exit(failed > 0 ? 1 : 0);
}

run().catch((err) => {
  console.error("Test runner error:", err);
  process.exit(1);
});
```

**Step 2: Run tests to verify they fail**

```bash
node test/dedup-detection.test.mjs
```

Expected: Tests fail with "dedup not implemented" or similar errors.

**Step 3: Commit test file**

```bash
git add test/dedup-detection.test.mjs
git commit -m "test: add dedup detection tests (failing)"
```

---

## Task 3: Implement getDedupConfig Helper

**Files:**

- Modify: `src/store.ts` (MemoryStore class)

**Step 1: Add getDedupConfig method**

Inside the `MemoryStore` class, add the helper method:

```typescript
private getDedupConfig(): Required<DedupConfig> {
  return {
    enabled: this.config.dedup?.enabled ?? DEFAULT_DEDUP_CONFIG.enabled,
    threshold: this.config.dedup?.threshold ?? DEFAULT_DEDUP_CONFIG.threshold,
    scopeMode: this.config.dedup?.scopeMode ?? DEFAULT_DEDUP_CONFIG.scopeMode,
  };
}
```

**Step 2: Commit**

```bash
git add src/store.ts
git commit -m "feat(store): add getDedupConfig helper"
```

---

## Task 4: Implement checkDuplicate Method

**Files:**

- Modify: `src/store.ts` (MemoryStore class)

**Step 1: Add checkDuplicate method**

Add this private method to the MemoryStore class. It should reuse the existing embedding and vector search infrastructure:

```typescript
private async checkDuplicate(
  text: string,
  config: Required<DedupConfig>,
  currentScope?: string,
): Promise<{ entry: MemoryEntry; similarity: number } | null> {
  try {
    // 1. Generate embedding (reuses embedder cache)
    const embedding = await this.embedder.embedPassage(text);

    // 2. Build scope filter based on scopeMode
    const scopeFilter = config.scopeMode === 'scope' && currentScope
      ? [currentScope]
      : undefined;

    // 3. Vector search for top-1 most similar
    const results = await this.vectorSearch(embedding, {
      limit: 1,
      scopeFilter,
    });

    // 4. Check threshold
    if (results.length > 0 && results[0].score >= config.threshold) {
      return {
        entry: results[0].entry,
        similarity: results[0].score,
      };
    }

    return null;

  } catch (err) {
    // Fail-open: dedup failure should not block storage
    console.warn({
      event: 'dedup_check_failed',
      error: err instanceof Error ? err.message : String(err),
      text: text.slice(0, 50),
    });
    return null;
  }
}
```

**Step 2: Commit**

```bash
git add src/store.ts
git commit -m "feat(store): implement checkDuplicate method with fail-open"
```

---

## Task 5: Integrate Dedup into memory_store

**Files:**

- Modify: `src/store.ts` (memory_store method)

**Step 1: Find the memory_store method**

Locate the `async memory_store(params: StoreParams)` method.

**Step 2: Add dedup check at the beginning**

Add this code block at the start of the method (after any parameter normalization):

```typescript
async memory_store(params: StoreParams): Promise<StoreResult> {
  const dedupConfig = this.getDedupConfig();

  // Dedup detection (can be disabled, can be forced to skip)
  if (dedupConfig.enabled && !params.force) {
    const dup = await this.checkDuplicate(
      params.text,
      dedupConfig,
      params.scope || this.defaultScope,
    );

    if (dup) {
      // Log the skip
      console.info({
        event: 'memory_dedup_skip',
        similarity: dup.similarity,
        threshold: dedupConfig.threshold,
        scopeMode: dedupConfig.scopeMode,
        newText: params.text.slice(0, 50),
        existingId: dup.entry.id,
        existingScope: dup.entry.scope,
      });

      // Return skipped result
      return {
        id: randomUUID(),
        status: 'skipped',
        reason: 'duplicate',
        similarity: dup.similarity,
        similarTo: {
          id: dup.entry.id,
          text: dup.entry.text.slice(0, 100) + (dup.entry.text.length > 100 ? '...' : ''),
          timestamp: dup.entry.timestamp,
          scope: dup.entry.scope,
        },
      };
    }
  }

  // ... existing storage logic continues here
}
```

**Step 3: Ensure existing storage returns correct format**

Make sure the existing storage path returns `{ id, status: 'stored' }`:

```typescript
// At the end of the successful storage path:
return {
  id: storedId,
  status: "stored",
};
```

**Step 4: Commit**

```bash
git add src/store.ts
git commit -m "feat(store): integrate dedup check into memory_store"
```

---

## Task 6: Update Tool Definition

**Files:**

- Modify: `src/tools.ts:547-688` (memory_store tool)

**Step 1: Update tool description**

Find the `memory_store` tool definition and update the description:

```typescript
{
  name: "memory_store",
  description: "Store a new memory entry. Automatically skips near-duplicates (similarity >= 92%) unless force is true. Returns 'skipped' status if duplicate detected.",
  inputSchema: {
    type: "object",
    properties: {
      text: {
        type: "string",
        description: "Memory content to store",
      },
      category: {
        type: "string",
        enum: ["preference", "fact", "decision", "entity", "other", "reflection"],
        description: "Memory category (default: other)",
      },
      scope: {
        type: "string",
        description: "Memory scope for isolation (default: current scope)",
      },
      importance: {
        type: "number",
        minimum: 0,
        maximum: 1,
        description: "Importance score 0-1 (default: 0.5)",
      },
      force: {
        type: "boolean",
        description: "Force store even if duplicate detected (default: false)",
      },
    },
    required: ["text"],
  },
}
```

**Step 2: Update tool handler to pass force parameter**

Find where `memory_store` is called and ensure `force` is passed:

```typescript
const result = await store.memory_store({
  text: params.text,
  category: params.category,
  scope: params.scope,
  importance: params.importance,
  metadata: params.metadata,
  force: params.force, // Add this line
});
```

**Step 3: Commit**

```bash
git add src/tools.ts
git commit -m "feat(tools): add force parameter to memory_store tool"
```

---

## Task 7: Run Tests and Fix Issues

**Step 1: Run the dedup tests**

```bash
node test/dedup-detection.test.mjs
```

**Step 2: Fix any failing tests**

If tests fail, debug and fix the implementation.

**Step 3: Run full test suite**

```bash
npm test
```

**Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve test failures"
```

---

## Task 8: Update Documentation

**Files:**

- Modify: `README.md`

**Step 1: Add dedup configuration section**

Add after the existing configuration section:

````markdown
## Deduplication

Memory store automatically detects and skips near-duplicate entries to prevent redundant storage.

### Configuration

```json
{
  "storage": {
    "dedup": {
      "enabled": true,
      "threshold": 0.92,
      "scopeMode": "scope"
    }
  }
}
```
````

| Option      | Type    | Default   | Description                                                    |
| ----------- | ------- | --------- | -------------------------------------------------------------- |
| `enabled`   | boolean | `true`    | Enable duplicate detection                                     |
| `threshold` | number  | `0.92`    | Similarity threshold (0-1). Higher = stricter                  |
| `scopeMode` | string  | `'scope'` | `'scope'` = dedup within scope, `'global'` = across all scopes |

### Force Storage

To bypass dedup and force storage:

```
memory_store({
  text: "Critical info that must be stored",
  force: true
})
```

### Behavior

- **Threshold 0.92**: Only skips highly similar content (>92% match)
- **Scope mode**: Different scopes can have intentional duplicates
- **Fail-open**: If dedup check fails, stores anyway (no data loss)

````

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add dedup configuration documentation"
````

---

## Task 9: Final Verification

**Step 1: Run all tests**

```bash
npm test
```

Expected: All tests pass.

**Step 2: Run linter/type check**

```bash
npm run lint || npm run typecheck
```

**Step 3: Create final commit**

```bash
git add -A
git commit -m "feat: implement similarity-based dedup detection (closes #30)

- Add DedupConfig with enabled/threshold/scopeMode options
- Implement checkDuplicate with fail-open error handling
- Integrate dedup check into memory_store with force bypass
- Add force parameter to memory_store tool
- Add comprehensive test coverage (7 test cases)
- Update README with dedup configuration docs

Closes #30"
```

---

## Task 10: Create Pull Request

**Step 1: Push to fork**

```bash
git push origin feat/dedup-detection
```

**Step 2: Create PR**

```bash
gh pr create --repo win4r/memory-lancedb-pro \
  --title "feat: Implement similarity-based dedup detection before memory_store" \
  --body "Closes #30

## Problem

Over time, the same knowledge gets stored multiple times in slightly different wording, leading to:
- Redundant entries crowding recall results
- Wasted tokens from duplicate content
- Degraded retrieval quality

## Solution

Add similarity-based duplicate detection before storage:
- Configurable threshold (default 0.92)
- Scope-isolated or global dedup mode
- Fail-open error handling
- Force bypass option

## Test Coverage

- ✅ Identical text detection
- ✅ Similar text (>92%) detection
- ✅ Different text stored normally
- ✅ Force bypass
- ✅ Scope isolation
- ✅ Global mode
- ✅ Disabled dedup

## Files Changed

- \`src/store.ts\` - Core implementation
- \`src/tools.ts\` - Tool definition
- \`test/dedup-detection.test.mjs\` - Tests
- \`README.md\` - Documentation"
```

---

## Summary

| Task | Description              | Commits |
| ---- | ------------------------ | ------- |
| 1    | Type definitions         | 1       |
| 2    | Write tests              | 1       |
| 3    | getDedupConfig           | 1       |
| 4    | checkDuplicate           | 1       |
| 5    | memory_store integration | 1       |
| 6    | Tool definition          | 1       |
| 7    | Test fixes               | 0-2     |
| 8    | Documentation            | 1       |
| 9    | Final verification       | 1       |
| 10   | PR creation              | 0       |

**Total commits: ~8-10**
