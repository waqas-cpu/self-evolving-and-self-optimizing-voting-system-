/** Hard safety bounds for aggregation (Gates L4-02, L4-06). */
export const AGGREGATION_CONFIG = {
  MIN_ORACLE_SOURCES: 3,
  /** Gate L4-06 */
  DEGRADED_MODE_THRESHOLD: 0.6,
  DEFAULT_METHOD: "median" as const,
  /** Population stdev; drop |x-mean| > k * sigma */
  OUTLIER_SIGMA: 2,
  /** Gate L4-08 */
  OFF_CHAIN_MAX_WEIGHT: 0.2,
} as const;
