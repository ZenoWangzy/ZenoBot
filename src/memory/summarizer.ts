/**
 * Memory summarizer.
 *
 * When chunks are demoted to the cold tier they may be summarized to
 * preserve essential meaning while reducing storage and token cost.
 * Summarization is opt-in and requires an LLM call.
 *
 * [LINK]:
 *   - TierThresholds / MemoryTierLabel -> ./tiering.ts
 *   - MemorySearchResult              -> ./types.ts
 *   - Schema                          -> ./memory-schema.ts
 */

import type { DatabaseSync } from "node:sqlite";
import { createSubsystemLogger } from "../logging/subsystem.js";

const log = createSubsystemLogger("memory/summarizer");

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type SummarizeOptions = {
  /** Maximum number of cold chunks to summarize per run. */
  batchSize?: number;
  /** If provided, call this function instead of the built-in prompt. */
  summarizeFn?: (text: string) => Promise<string>;
};

export type SummarizeResult = {
  summarized: number;
  skipped: number;
  errors: number;
};

// ---------------------------------------------------------------------------
// Built-in summarization prompt
// ---------------------------------------------------------------------------

const SUMMARIZE_SYSTEM = `You are a memory compressor. Given a chunk of memory text, produce a concise summary that preserves:
- Key decisions and their rationale
- Important facts, names, dates
- User preferences and constraints
- Action items and their status

Output ONLY the summary, no preamble. Keep it under 200 words.`;

/**
 * Default summarization function using a simple template.
 * In production, this would call an LLM. For now it performs a
 * deterministic extraction of the most important lines.
 */
function defaultSummarize(text: string): string {
  const lines = text.split("\n").filter((l) => l.trim().length > 0);
  if (lines.length <= 5) {
    return text.trim();
  }

  // Heuristic: keep headers, lines with importance/decision keywords,
  // and first + last content lines.
  const important = lines.filter(
    (l) =>
      l.startsWith("#") ||
      /\b(decision|important|action|preference|todo|deadline|critical)\b/i.test(l),
  );

  const kept = new Set<string>();
  // Always keep first and last lines
  if (lines[0]) {
    kept.add(lines[0]);
  }
  if (lines[lines.length - 1]) {
    kept.add(lines[lines.length - 1]);
  }
  for (const line of important) {
    kept.add(line);
  }

  // If we haven't captured enough, add more from the start
  for (const line of lines) {
    if (kept.size >= 8) {
      break;
    }
    kept.add(line);
  }

  return [...kept].join("\n").trim();
}

// ---------------------------------------------------------------------------
// Batch summarization
// ---------------------------------------------------------------------------

/**
 * Summarize cold chunks that haven't been summarized yet.
 *
 * A chunk is considered "unsummarized" if it's in the cold tier and
 * its text length exceeds a threshold (meaning it can be compressed).
 */
export async function summarizeColdChunks(params: {
  db: DatabaseSync;
  options?: SummarizeOptions;
}): Promise<SummarizeResult> {
  const batchSize = params.options?.batchSize ?? 20;
  const summarizeFn = params.options?.summarizeFn;

  // Find cold chunks whose text is long enough to benefit from summarization
  const rows = params.db
    .prepare(
      `SELECT id, text FROM chunks
       WHERE tier = 'cold' AND LENGTH(text) > 500
       ORDER BY last_access ASC
       LIMIT ?`,
    )
    .all(batchSize) as Array<{ id: string; text: string }>;

  let summarized = 0;
  let skipped = 0;
  let errors = 0;

  const updateStmt = params.db.prepare(`UPDATE chunks SET text = ? WHERE id = ?`);

  for (const row of rows) {
    try {
      const summary = summarizeFn ? await summarizeFn(row.text) : defaultSummarize(row.text);

      if (summary.length >= row.text.length) {
        // Summary wasn't shorter — skip
        skipped++;
        continue;
      }

      updateStmt.run(summary, row.id);
      summarized++;
    } catch (err) {
      log.debug(`summarize failed for chunk ${row.id}: ${String(err)}`);
      errors++;
    }
  }

  log.debug(`summarizer: summarized=${summarized} skipped=${skipped} errors=${errors}`);

  return { summarized, skipped, errors };
}

/**
 * Return the built-in system prompt for LLM-based summarization.
 * Exposed for consumers that want to use it with their own LLM client.
 */
export function getSummarizeSystemPrompt(): string {
  return SUMMARIZE_SYSTEM;
}
