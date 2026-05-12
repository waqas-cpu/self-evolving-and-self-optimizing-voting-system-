/** Gate L4-04 — max age per metric class (seconds). */
export const FRESHNESS_RULES = {
  TOKEN_PRICE: 300,
  TREASURY_VELOCITY: 3600,
  VOTER_TURNOUT: 86400,
} as const;

export type FreshnessMetricKey = keyof typeof FRESHNESS_RULES;

export function freshnessScoreBps(nowSec: number, reportedAtSec: number, maxAgeSec: number): number {
  if (nowSec < reportedAtSec) return 0;
  const age = nowSec - reportedAtSec;
  if (age > maxAgeSec) return 0;
  return Math.round((1 - age / maxAgeSec) * 10_000);
}
