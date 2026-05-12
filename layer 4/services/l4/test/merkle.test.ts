import { describe, expect, it } from "@jest/globals";
import { buildMerkleRoot, getProof, metricLeafHash, verifyLeaf } from "../src/crypto/MerkleBuilder.js";

describe("MerkleBuilder", () => {
  it("builds root and proofs compatible with on-chain encoding", () => {
    const leaves = [
      metricLeafHash({
        metricId: `0x${"01".repeat(32)}`,
        value: 100n,
        confidenceScore: 9_500n,
        freshnessScore: 9_900n,
        blockHeight: 1n,
        sourceCount: 3n,
      }),
      metricLeafHash({
        metricId: `0x${"02".repeat(32)}`,
        value: 200n,
        confidenceScore: 9_000n,
        freshnessScore: 9_800n,
        blockHeight: 1n,
        sourceCount: 3n,
      }),
      metricLeafHash({
        metricId: `0x${"03".repeat(32)}`,
        value: 300n,
        confidenceScore: 8_800n,
        freshnessScore: 9_700n,
        blockHeight: 1n,
        sourceCount: 3n,
      }),
    ];
    const root = buildMerkleRoot(leaves);
    for (let i = 0; i < leaves.length; i++) {
      const proof = getProof(leaves, i);
      expect(verifyLeaf(root, leaves[i]!, proof)).toBe(true);
    }
  });
});
