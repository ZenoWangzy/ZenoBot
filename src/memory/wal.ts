/**
 * Write-Ahead Log (WAL) for crash-safe memory writes.
 *
 * Before a memory write is committed, it is first recorded in the WAL
 * table.  If the process crashes mid-write, the WAL can be replayed on
 * next startup to recover the pending operation.
 *
 * [LINK]:
 *   - Schema -> ./memory-schema.ts
 */

import type { DatabaseSync } from "node:sqlite";
import { createSubsystemLogger } from "../logging/subsystem.js";

const log = createSubsystemLogger("memory/wal");

// ---------------------------------------------------------------------------
// Schema
// ---------------------------------------------------------------------------

const WAL_TABLE = "memory_wal";

/**
 * Ensure the WAL table exists.  Safe to call multiple times.
 */
export function ensureWalSchema(db: DatabaseSync): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS ${WAL_TABLE} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      op TEXT NOT NULL,
      path TEXT NOT NULL,
      payload TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL,
      completed_at INTEGER
    );
  `);
  db.exec(`CREATE INDEX IF NOT EXISTS idx_wal_completed ON ${WAL_TABLE}(completed_at);`);
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type WalOperation = "write" | "delete" | "update";

export type WalEntry = {
  id: number;
  op: WalOperation;
  path: string;
  payload: string;
  createdAt: number;
  completedAt: number | null;
};

// ---------------------------------------------------------------------------
// Write operations
// ---------------------------------------------------------------------------

/**
 * Record an intent to write/update/delete a memory file.
 * Returns the WAL entry id.
 */
export function walBegin(params: {
  db: DatabaseSync;
  op: WalOperation;
  path: string;
  payload?: string;
}): number {
  const now = Date.now();
  const result = params.db
    .prepare(`INSERT INTO ${WAL_TABLE} (op, path, payload, created_at) VALUES (?, ?, ?, ?)`)
    .run(params.op, params.path, params.payload ?? "", now);
  return Number((result as unknown as { lastInsertRowid?: number | bigint }).lastInsertRowid ?? 0);
}

/**
 * Mark a WAL entry as completed (the write succeeded).
 */
export function walComplete(params: { db: DatabaseSync; id: number }): void {
  params.db
    .prepare(`UPDATE ${WAL_TABLE} SET completed_at = ? WHERE id = ?`)
    .run(Date.now(), params.id);
}

/**
 * Get all incomplete WAL entries (potential crash recovery candidates).
 */
export function walGetPending(db: DatabaseSync): WalEntry[] {
  const rows = db
    .prepare(
      `SELECT id, op, path, payload, created_at, completed_at
       FROM ${WAL_TABLE}
       WHERE completed_at IS NULL
       ORDER BY created_at ASC`,
    )
    .all() as Array<{
    id: number;
    op: string;
    path: string;
    payload: string;
    created_at: number;
    completed_at: number | null;
  }>;

  return rows.map((row) => ({
    id: row.id,
    op: row.op as WalOperation,
    path: row.path,
    payload: row.payload,
    createdAt: row.created_at,
    completedAt: row.completed_at,
  }));
}

// ---------------------------------------------------------------------------
// Cleanup
// ---------------------------------------------------------------------------

/**
 * Remove completed WAL entries older than `maxAgeMs` (default: 7 days).
 */
export function walCleanup(params: { db: DatabaseSync; maxAgeMs?: number }): number {
  const cutoff = Date.now() - (params.maxAgeMs ?? 7 * 24 * 60 * 60 * 1000);
  const result = params.db
    .prepare(`DELETE FROM ${WAL_TABLE} WHERE completed_at IS NOT NULL AND completed_at < ?`)
    .run(cutoff);
  return Number((result as unknown as { changes?: number }).changes ?? 0);
}

// ---------------------------------------------------------------------------
// Recovery
// ---------------------------------------------------------------------------

/**
 * Replay pending WAL entries.  The caller provides a `replayFn` that
 * performs the actual file-system operation for each entry.
 *
 * Returns the number of entries successfully replayed.
 */
export async function walReplay(params: {
  db: DatabaseSync;
  replayFn: (entry: WalEntry) => Promise<boolean>;
}): Promise<number> {
  const pending = walGetPending(params.db);
  if (pending.length === 0) {
    return 0;
  }

  log.debug(`WAL recovery: ${pending.length} pending entries`);
  let replayed = 0;

  for (const entry of pending) {
    try {
      const ok = await params.replayFn(entry);
      if (ok) {
        walComplete({ db: params.db, id: entry.id });
        replayed++;
      }
    } catch (err) {
      log.debug(`WAL replay failed for entry ${entry.id}: ${String(err)}`);
    }
  }

  log.debug(`WAL recovery: replayed ${replayed}/${pending.length}`);
  return replayed;
}
