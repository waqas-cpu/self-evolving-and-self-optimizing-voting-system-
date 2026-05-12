import { AGGREGATION_CONFIG } from "../config/aggregation.config.js";
import type { DataSourceSample } from "../types/index.js";

export type ConflictStrategy = "median_breaker" | "require_unanimous_band";

/**
 * When oracle families diverge beyond tolerance, pick a conservative resolution.
 */
export function resolveConflict(params: {
  samples: DataSourceSample[];
  relativeBandBps: number;
  strategy: ConflictStrategy;
}): { winner: DataSourceSample[]; dropped: string[] } {
  if (params.samples.length < AGGREGATION_CONFIG.MIN_ORACLE_SOURCES) {
    return { winner: [], dropped: params.samples.map((s) => s.id) };
  }
  const sorted = [...params.samples].sort((a, b) => (a.value < b.value ? -1 : a.value > b.value ? 1 : 0));
  const mid = sorted[Math.floor(sorted.length / 2)]!.value;
  const band = (mid * BigInt(params.relativeBandBps)) / 10_000n;
  const kept = sorted.filter((s) => s.value >= mid - band && s.value <= mid + band);
  const dropped = sorted.filter((s) => !kept.includes(s)).map((s) => s.id);

  if (params.strategy === "require_unanimous_band" && kept.length !== sorted.length) {
    return { winner: [], dropped: sorted.map((s) => s.id) };
  }
  if (kept.length < AGGREGATION_CONFIG.MIN_ORACLE_SOURCES) {
    return { winner: [], dropped: sorted.map((s) => s.id) };
  }
  return { winner: kept, dropped };
}
