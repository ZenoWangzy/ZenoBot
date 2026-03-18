# Memory Dedup Detection Design

> **Project**: memory-lancedb-pro (https://github.com/win4r/memory-lancedb-pro)
> **Issue**: #30 - Similarity-based dedup detection before memory_store
> **Date**: 2026-03-07
> **Status**: Approved

---

## Problem Statement

Over time, the same knowledge gets stored multiple times in slightly different wording:

- **Redundant entries**: Top-5 recall results all saying the same thing
- **Wasted tokens**: Each recall returns near-duplicate content
- **Degraded retrieval quality**: Important memories get crowded out by duplicates

This is especially problematic with `autoCapture` enabled in high-frequency chat scenarios.

---

## Design Decisions

| Decision         | Choice            | Rationale                                          |
| ---------------- | ----------------- | -------------------------------------------------- |
| Default behavior | **skip** (silent) | Returns structured status, suitable for automation |
| Detection mode   | **synchronous**   | Immediate feedback, simpler implementation         |
| Threshold config | **global**        | All scopes share same threshold                    |
| Error handling   | **fail-open**     | Dedup failure never blocks storage                 |
| Scope isolation  | **configurable**  | `scopeMode: 'scope' \| 'global'`                   |

---

## Configuration Schema

```typescript
export interface StoreConfig {
  dbPath: string;
  vectorDim: number;

  // Deduplication configuration
  dedup?: {
    /** Enable duplicate detection (default: true) */
    enabled?: boolean;
    /** Similarity threshold 0-1 (default: 0.92) */
    threshold?: number;
    /** Dedup scope: 'scope' = current scope only, 'global' = all scopes (default: 'scope') */
    scopeMode?: "scope" | "global";
  };
}
```

### Default Values

```typescript
const DEFAULT_DEDUP_CONFIG = {
  enabled: true,
  threshold: 0.92, // Reduced from 0.90 to minimize false positives
  scopeMode: "scope",
};
```

---

## API Changes

### StoreParams Extension

```typescript
export interface StoreParams {
  text: string;
  category?: MemoryEntry["category"];
  scope?: string;
  importance?: number;
  metadata?: Record<string, unknown>;
  force?: boolean; // NEW: Force store even if duplicate detected
}
```

### StoreResult Extension

```typescript
export interface StoreResult {
  id: string;
  status: "stored" | "skipped";
  reason?: "duplicate"; // NEW
  similarity?: number; // NEW
  similarTo?: {
    // NEW
    id: string;
    text: string;
    timestamp: number;
    scope: string;
  };
}
```

---

## Implementation

### checkDuplicate Method

```typescript
private async checkDuplicate(
  text: string,
  config: StoreDedupConfig,
  currentScope?: string,
): Promise<{ entry: MemoryEntry; similarity: number } | null> {
  try {
    // 1. Generate embedding (reuses cache)
    const embedding = await this.embedder.embedPassage(text);

    // 2. Build scope filter
    const scopeFilter = config.scopeMode === 'scope' && currentScope
      ? [currentScope]
      : undefined;

    // 3. Vector search top-1
    const results = await this.vectorSearch(embedding, {
      limit: 1,
      scopeFilter,
    });

    // 4. Threshold check
    if (results.length > 0 && results[0].score >= config.threshold) {
      return { entry: results[0].entry, similarity: results[0].score };
    }
    return null;

  } catch (err) {
    // Fail-open: dedup failure doesn't block storage
    logger.warn({
      event: 'dedup_check_failed',
      error: err instanceof Error ? err.message : String(err),
      text: text.slice(0, 50),
    });
    return null;
  }
}
```

### memory_store Integration

```typescript
async memory_store(params: StoreParams): Promise<StoreResult> {
  const dedupConfig = this.getDedupConfig();

  // Dedup check (can be disabled, can be forced to skip)
  if (dedupConfig.enabled && !params.force) {
    const dup = await this.checkDuplicate(
      params.text,
      dedupConfig,
      params.scope || this.defaultScope,
    );

    if (dup) {
      logger.info({
        event: 'memory_dedup_skip',
        similarity: dup.similarity,
        threshold: dedupConfig.threshold,
        scopeMode: dedupConfig.scopeMode,
        newText: params.text.slice(0, 50),
        existingId: dup.entry.id,
        existingScope: dup.entry.scope,
      });

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

  // Original storage logic...
}
```

---

## Tool Definition

```typescript
{
  name: 'memory_store',
  description: 'Store a new memory entry. Automatically skips near-duplicates unless force is true.',
  inputSchema: {
    type: 'object',
    properties: {
      text: { type: 'string', description: 'Memory content to store' },
      category: { type: 'string', enum: ['preference', 'fact', 'decision', 'entity', 'other', 'reflection'] },
      scope: { type: 'string', description: 'Memory scope for isolation' },
      importance: { type: 'number', minimum: 0, maximum: 1 },
      force: { type: 'boolean', description: 'Force store even if duplicate detected (default: false)' },
    },
    required: ['text'],
  },
}
```

---

## Test Coverage

| Test            | Description                                              |
| --------------- | -------------------------------------------------------- |
| Identical text  | Same text should be skipped with similarity >= 0.99      |
| Similar text    | >92% similarity should be detected and skipped           |
| Different text  | Unrelated content should be stored normally              |
| Force bypass    | `force: true` should store regardless of duplicate       |
| Scope isolation | Different scopes should allow duplicates in 'scope' mode |
| Global mode     | Same content across scopes should be deduplicated        |
| Disabled dedup  | `enabled: false` should store all content                |
| Fail-open       | Embedding/search failure should not block storage        |
| Empty text      | Edge case handling                                       |
| Long text       | Performance with 10,000+ character texts                 |

---

## Performance Considerations

| Metric                | Estimate | Notes                               |
| --------------------- | -------- | ----------------------------------- |
| Embedding latency     | 50-200ms | Remote API, cached for similar text |
| Vector search latency | 10-50ms  | LanceDB ANN search                  |
| Total dedup overhead  | 60-250ms | Only when dedup enabled             |
| Cache hit rate        | ~60-80%  | For similar content patterns        |

---

## Backward Compatibility

- **Existing calls**: No changes required
- **Default behavior**: Dedup enabled with safe defaults
- **Return type**: Extended but backward compatible
- **Configuration**: Optional, uses defaults if not specified

---

## Files to Modify

1. `src/store.ts` - Core implementation
2. `src/tools.ts` - Tool definition update
3. `README.md` - Configuration documentation
4. `test/dedup-detection.mjs` - New test file

---

## References

- Issue: https://github.com/win4r/memory-lancedb-pro/issues/30
- Similar PR: #45 (fail-open dedup pre-check pattern)
