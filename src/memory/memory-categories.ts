/**
 * Memory categories and importance levels.
 * TODO: Implement full categorization functionality.
 */

export type MemoryCategory =
  | "conversation"
  | "preference"
  | "fact"
  | "task"
  | "error"
  | "debug"
  | "context"
  | "reference"
  | "decision"
  | "note"
  | "action";

export type MemoryImportance = "low" | "medium" | "high" | "critical";

export const DEFAULT_CATEGORIES: MemoryCategory[] = [
  "conversation",
  "preference",
  "fact",
  "task",
  "context",
  "decision",
  "note",
  "action",
];

export const CATEGORY_IMPORTANCE: Record<MemoryCategory, MemoryImportance> = {
  conversation: "medium",
  preference: "high",
  fact: "high",
  task: "medium",
  error: "high",
  debug: "low",
  context: "medium",
  reference: "low",
  decision: "high",
  note: "low",
  action: "high",
};
