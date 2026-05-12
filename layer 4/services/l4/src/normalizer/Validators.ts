import type { Layer3Input } from "../types/index.js";

export function assertBpsRange(label: string, v: bigint, max = 10_000n): void {
  if (v < 0n || v > max) {
    throw new Error(`${label} out of range: ${v}`);
  }
}

export function validateLayer3Input(input: Layer3Input): { valid: boolean; errors: string[] } {
  const errors: string[] = [];
  if (!input.metadata.batchId) errors.push("missing_batchId");
  if (input.metadata.blockNumber < 0) errors.push("bad_blockNumber");
  if (!/^0x[0-9a-f]{64}$/i.test(input.metadata.merkleRoot)) errors.push("bad_merkleRoot");
  try {
    assertBpsRange("voterTurnoutBps", input.onChain.voterTurnoutBps);
  } catch (e) {
    errors.push(e instanceof Error ? e.message : String(e));
  }
  const oc = input.offChain;
  if (oc.tokenPriceUsd < 0 || oc.marketVolatility < 0) errors.push("negative_offchain");
  if (oc.sentimentScore !== undefined && (oc.sentimentScore < 0 || oc.sentimentScore > 1)) {
    errors.push("sentiment_range");
  }
  return { valid: errors.length === 0, errors };
}
