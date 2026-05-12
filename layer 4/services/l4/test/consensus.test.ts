import { describe, expect, it } from "@jest/globals";
import { runConsensus } from "../src/aggregation/ConsensusEngine.js";
import { FRESHNESS_RULES } from "../src/config/freshness.js";

describe("ConsensusEngine", () => {
  it("requires at least 3 fresh sources", () => {
    const now = 1_000_000;
    const out = runConsensus({
      samples: [
        { id: "a", kind: "oracle", value: 100n, timestamp: now - 10, confidence: 0.9, operator: "o1" },
        { id: "b", kind: "oracle", value: 102n, timestamp: now - 10, confidence: 0.9, operator: "o2" },
      ],
      nowSec: now,
      maxDataAgeSec: FRESHNESS_RULES.TOKEN_PRICE,
    });
    expect(out.ok).toBe(false);
  });

  it("median aggregates and flags outliers", () => {
    const now = 2_000_000;
    const out = runConsensus({
      samples: [
        { id: "a", kind: "oracle", value: 100n, timestamp: now - 5, confidence: 0.95, operator: "o1" },
        { id: "b", kind: "oracle", value: 102n, timestamp: now - 5, confidence: 0.95, operator: "o2" },
        { id: "c", kind: "oracle", value: 104n, timestamp: now - 5, confidence: 0.95, operator: "o3" },
        { id: "d", kind: "oracle", value: 10_000n, timestamp: now - 5, confidence: 0.5, operator: "o4" },
      ],
      nowSec: now,
      maxDataAgeSec: FRESHNESS_RULES.TOKEN_PRICE,
    });
    expect(out.ok).toBe(true);
    expect(out.aggregate?.sourceCount).toBeGreaterThanOrEqual(3);
    expect(out.aggregate?.suspectSources.length).toBeGreaterThan(0);
  });
});
