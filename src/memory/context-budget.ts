/**
 * Dynamic context budget calculator for memory preloading.
 *
 * Determines how many tokens can be safely allocated to pre-injected
 * memory snippets without starving the model's response or tool calls.
 */

/** Absolute floor — never allocate less than this many tokens. */
const MIN_BUDGET_TOKENS = 200;
/** Hard ceiling — never allocate more than this. */
const MAX_BUDGET_TOKENS = 8000;
/** Default fraction of the context window reserved for memory. */
const DEFAULT_FRACTION = 0.1;
/** Extra headroom when tools are active (tool results eat tokens). */
const TOOL_HEADROOM_TOKENS = 4000;

export function calculateMemoryBudget(params: {
  /** Model context window size in tokens. */
  contextWindow: number;
  /** Tokens already consumed (system prompt + history). */
  currentTokens: number;
  /** Tokens reserved for the model's response. */
  reserveForResponse: number;
  /** Whether the session has tools enabled. */
  hasTools: boolean;
}): number {
  const available =
    params.contextWindow -
    params.currentTokens -
    params.reserveForResponse -
    (params.hasTools ? TOOL_HEADROOM_TOKENS : 0);

  if (available <= MIN_BUDGET_TOKENS) {
    return 0; // no room for memory
  }

  const proportional = Math.floor(params.contextWindow * DEFAULT_FRACTION);
  const budget = Math.min(available, proportional, MAX_BUDGET_TOKENS);
  return Math.max(budget, MIN_BUDGET_TOKENS);
}

/**
 * Estimate token count for a snippet of text.
 * Rough heuristic: 1 token ≈ 4 chars for English, 1.5 chars for CJK-heavy text.
 */
export function estimateTokens(text: string): number {
  // Quick CJK ratio check
  const cjkChars = (text.match(/[\u4e00-\u9fff\u3400-\u4dbf]/g) ?? []).length;
  const ratio = text.length > 0 ? cjkChars / text.length : 0;
  const charsPerToken = ratio > 0.3 ? 1.5 : 4;
  return Math.ceil(text.length / charsPerToken);
}
