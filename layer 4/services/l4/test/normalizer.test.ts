import { describe, expect, it } from "@jest/globals";
import { NormalizationEngine } from "../src/normalizer/NormalizationEngine.js";

describe("NormalizationEngine", () => {
  it("caps off-chain sentiment to 20%", () => {
    const n = new NormalizationEngine();
    const out = n.normalize({
      metadata: {
        batchId: "b1",
        timestamp: 1,
        blockNumber: 1,
        merkleRoot: `0x${"ab".repeat(32)}`,
      },
      onChain: {
        proposalId: 1n,
        voterTurnoutBps: 6000n,
        totalVoiceCreditsUsed: 0n,
        treasuryInflow: 0n,
        treasuryOutflow: 0n,
        tokenPriceUsd: 2000n,
        timestamp: 1,
        blockHash: `0x${"00".repeat(32)}`,
      },
      offChain: { tokenPriceUsd: 1, marketVolatility: 0.9, sentimentScore: 0.99 },
      provenance: { signatures: [], sources: [], consensusMethod: "median", attestationTypes: [] },
    });
    expect(out.offChain.sentimentScore).toBeLessThanOrEqual(0.2 + 1e-9);
    expect(out.offChain.marketVolatility).toBeLessThanOrEqual(0.2 + 1e-9);
  });
});
