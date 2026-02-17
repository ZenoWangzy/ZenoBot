/**
 * Memory tiering utilities.
 * TODO: Implement full tiering functionality.
 */

import type { DatabaseSync } from "node:sqlite";

export interface TierStats {
  hot: number;
  warm: number;
  cold: number;
  total: number;
  byMonth: Record<string, number>;
}

export function getTierStats(db: DatabaseSync): TierStats {
  // TODO: Implement actual tier stats calculation
  return {
    hot: 0,
    warm: 0,
    cold: 0,
    total: 0,
    byMonth: {},
  };
}
