import type { OnChainMetricsView } from "../types/index.js";

/**
 * Block-anchored snapshot helper — production wires RPC `eth_call` into `OnChainDataProvider.getMetrics`.
 */
export class OnChainIndexer {
  constructor(private readonly blockAnchor: number) {}

  anchor(): number {
    return this.blockAnchor;
  }

  /** Placeholder aggregate until RPC-backed reads are configured. */
  snapshotMetrics(_proposalId: bigint): OnChainMetricsView {
    void _proposalId;
    return {
      proposalId: 0n,
      voterTurnoutBps: 5_000n,
      totalVoiceCreditsUsed: 0n,
      treasuryInflow: 0n,
      treasuryOutflow: 0n,
      tokenPriceUsd: 2_000_00000000n,
      timestamp: Math.floor(Date.now() / 1000),
      blockHash: `0x${"00".repeat(32)}`,
    };
  }
}
