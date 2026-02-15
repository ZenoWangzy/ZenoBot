/**
 * Operation retry wrapper for browser automation stability.
 *
 * Provides automatic retry with exponential backoff for browser operations
 * that may fail due to transient connection issues.
 */

// Errors that indicate a retryable transient failure
const RETRYABLE_ERROR_PATTERNS = [
  "target closed",
  "session closed",
  "browser closed",
  "browser disconnected",
  "websocket",
  "connection",
  "disconnected",
  "net::err",
  "timeout",
  "execution context was destroyed",
];

// Operations that should NOT be retried (not idempotent)
const NON_RETRYABLE_OPERATIONS = [
  "setInputFiles", // File upload may partially complete
  "fillForm", // Form filling may partially complete
];

/**
 * Check if an error indicates a retryable transient failure.
 */
export function isRetryableError(err: unknown): boolean {
  if (!(err instanceof Error)) {
    const msg = String(err).toLowerCase();
    return RETRYABLE_ERROR_PATTERNS.some((pattern) => msg.includes(pattern));
  }

  const msg = err.message.toLowerCase();
  return RETRYABLE_ERROR_PATTERNS.some((pattern) => msg.includes(pattern));
}

/**
 * Check if an error indicates a connection-related failure.
 */
export function isConnectionError(err: unknown): boolean {
  if (!(err instanceof Error)) {
    return false;
  }
  const msg = err.message.toLowerCase();
  return (
    msg.includes("websocket") ||
    msg.includes("connection") ||
    msg.includes("disconnected") ||
    msg.includes("browser closed")
  );
}

/**
 * Check if an operation name should not be retried.
 */
export function isNonRetryableOperation(operationName: string): boolean {
  const lower = operationName.toLowerCase();
  return NON_RETRYABLE_OPERATIONS.some((op) => lower.includes(op.toLowerCase()));
}

export interface OperationRetryOptions {
  /** Maximum number of retry attempts (default: 3) */
  maxRetries?: number;
  /** Initial delay in milliseconds (default: 500) */
  initialDelayMs?: number;
  /** Maximum delay in milliseconds (default: 10000) */
  maxDelayMs?: number;
  /** Whether to clear connection cache on connection errors (default: true) */
  clearCacheOnConnectionError?: boolean;
  /** Operation name for non-idempotent operation detection */
  operationName?: string;
  /** Callback to clear the browser connection cache */
  clearBrowserCache?: () => void;
}

const DEFAULT_RETRY_OPTIONS: Required<Omit<OperationRetryOptions, "operationName" | "clearBrowserCache">> = {
  maxRetries: 3,
  initialDelayMs: 500,
  maxDelayMs: 10000,
  clearCacheOnConnectionError: true,
};

/**
 * Execute a browser operation with automatic retry on transient failures.
 *
 * Features:
 * - Exponential backoff with jitter
 * - Smart error classification (retryable vs non-retryable)
 * - Connection cache clearing on connection errors
 * - Protection for non-idempotent operations
 *
 * @example
 * ```typescript
 * const result = await withBrowserRetry(
 *   async () => page.click('button'),
 *   { operationName: 'click', clearBrowserCache: () => { cached = null; } }
 * );
 * ```
 */
export async function withBrowserRetry<T>(
  operation: () => Promise<T>,
  options?: OperationRetryOptions
): Promise<T> {
  const opts = { ...DEFAULT_RETRY_OPTIONS, ...options };
  let lastError: Error | undefined;
  let delay = opts.initialDelayMs;

  // Check if operation is non-retryable
  if (opts.operationName && isNonRetryableOperation(opts.operationName)) {
    return operation();
  }

  for (let attempt = 0; attempt <= opts.maxRetries; attempt++) {
    try {
      return await operation();
    } catch (err) {
      lastError = err instanceof Error ? err : new Error(String(err));

      // Don't retry non-retryable errors
      if (!isRetryableError(err)) {
        throw lastError;
      }

      // Clear connection cache on connection errors to trigger reconnect
      if (opts.clearCacheOnConnectionError && isConnectionError(err) && opts.clearBrowserCache) {
        opts.clearBrowserCache();
      }

      // Last attempt, don't wait
      if (attempt === opts.maxRetries) {
        break;
      }

      // Add jitter (0-30% of delay)
      const jitter = delay * 0.3 * Math.random();
      await new Promise((r) => setTimeout(r, delay + jitter));

      // Exponential backoff with max cap
      delay = Math.min(delay * 2, opts.maxDelayMs);
    }
  }

  throw lastError;
}

/**
 * Create a retry wrapper with pre-configured options.
 * Useful for wrapping multiple operations with the same settings.
 */
export function createRetryWrapper(
  options: OperationRetryOptions
): <T>(operation: () => Promise<T>, operationName?: string) => Promise<T> {
  return <T>(operation: () => Promise<T>, operationName?: string) =>
    withBrowserRetry(operation, { ...options, operationName });
}
