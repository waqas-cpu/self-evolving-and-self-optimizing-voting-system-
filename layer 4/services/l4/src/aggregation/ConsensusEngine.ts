import { AGGREGATION_CONFIG } from "../config/aggregation.config.js";
import type { AggregatedNumeric, DataSourceSample } from "../types/index.js";

function medianBigint(values: bigint[]): bigint {
  const s = [...values].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  const mid = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2n;
}

/** Robust scale: median absolute deviation from the sample median, ×1.4826 ≈ σ for Normal. */
function medianAbsDeviationScale(values: bigint[]): number {
  if (values.length === 0) return 1;
  const med = medianBigint(values);
  const center = Number(med);
  const absDev = values.map((v) => Math.abs(Number(v) - center)).sort((a, b) => a - b);
  const mad = absDev[Math.floor(absDev.length / 2)] ?? 1;
  return mad * 1.4826 || 1;
}

export interface ConsensusInput {
  samples: DataSourceSample[];
  nowSec: number;
  maxDataAgeSec: number;
  method?: "median" | "trimmed_mean" | "consensus_threshold";
}

export interface ConsensusOutput {
  ok: boolean;
  degraded: boolean;
  aggregate?: AggregatedNumeric;
  reason?: string;
}

/**
 * Gate L4-02 — ≥3 independent sources, median default, >2σ flagged as suspect and dropped.
 */
export function runConsensus(input: ConsensusInput): ConsensusOutput {
  const method = input.method ?? AGGREGATION_CONFIG.DEFAULT_METHOD;
  const expected = Math.max(AGGREGATION_CONFIG.MIN_ORACLE_SOURCES, input.samples.length);
  const responseRate = input.samples.length / Math.max(expected, 1);
  const degraded = responseRate < AGGREGATION_CONFIG.DEGRADED_MODE_THRESHOLD;

  const fresh = input.samples.filter((s) => input.nowSec - s.timestamp <= input.maxDataAgeSec);
  if (fresh.length < AGGREGATION_CONFIG.MIN_ORACLE_SOURCES) {
    return {
      ok: false,
      degraded: true,
      reason: "insufficient_fresh_sources",
    };
  }

  const values = fresh.map((s) => s.value);
  const med = medianBigint(values);
  const center = Number(med);
  const sigma = medianAbsDeviationScale(values);
  const kept: DataSourceSample[] = [];
  const suspect: string[] = [];
  for (const s of fresh) {
    if (Math.abs(Number(s.value) - center) <= AGGREGATION_CONFIG.OUTLIER_SIGMA * sigma) {
      kept.push(s);
    } else {
      suspect.push(s.id);
    }
  }

  if (kept.length < AGGREGATION_CONFIG.MIN_ORACLE_SOURCES) {
    return {
      ok: false,
      degraded: true,
      reason: "outliers_removed_too_many_sources",
    };
  }

  const keptVals = kept.map((k) => k.value);
  const value = method === "median" ? medianBigint(keptVals) : medianBigint(keptVals);

  const minTs = Math.min(...kept.map((k) => k.timestamp));
  const freshnessBps = Math.max(
    0,
    Math.round((1 - (input.nowSec - minTs) / input.maxDataAgeSec) * 10_000)
  );

  const avgConf = kept.reduce((a, s) => a + s.confidence, 0) / kept.length;
  const deviationPenalty = Math.min(suspect.length * 500, 4000);
  const confidenceBps = Math.max(0, Math.round(avgConf * 10_000) - deviationPenalty);

  return {
    ok: true,
    degraded,
    aggregate: {
      value,
      confidenceBps,
      freshnessBps,
      sourceCount: kept.length,
      suspectSources: suspect,
      method,
    },
  };
}
