/**
 * Memory preloader configuration.
 * TODO: Implement full preloader functionality.
 */

import type { MemorySearchManager } from "./index.js";

export interface PreloadConfig {
  enabled?: boolean;
  maxItems?: number;
  maxTokens?: number;
  scope?: "session" | "agent" | "global";
  filters?: {
    categories?: string[];
    minImportance?: number;
    maxAge?: number;
  };
}

export interface PreloadedMemory {
  id: string;
  content: string;
  tokens: number;
  category?: string;
  importance?: number;
  createdAt?: number;
}

export async function preloadMemory(params: {
  userMessage: string;
  sessionKey?: string;
  manager: MemorySearchManager;
  config?: PreloadConfig;
}): Promise<PreloadedMemory[]> {
  // TODO: Implement actual preload logic
  return [];
}

export function formatPreloadedMemorySection(memories: PreloadedMemory[]): string {
  if (memories.length === 0) {
    return "";
  }
  const lines = ["<relevant_memories>"];
  for (const mem of memories) {
    lines.push(`- ${mem.content}`);
  }
  lines.push("</relevant_memories>");
  return lines.join("\n");
}

export function resolvePreloadConfig(input?: Partial<PreloadConfig>): PreloadConfig {
  const defaults: PreloadConfig = {
    enabled: false,
    maxItems: 100,
    maxTokens: 2000,
    scope: "agent",
    filters: {
      categories: [],
      minImportance: 0,
    },
  };

  if (!input) {
    return defaults;
  }

  return {
    ...defaults,
    ...input,
    filters: {
      ...defaults.filters,
      ...input.filters,
    },
  };
}
