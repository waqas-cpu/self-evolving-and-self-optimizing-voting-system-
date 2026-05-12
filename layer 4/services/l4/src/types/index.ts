/** Layer 4 cross-module types (horizontal + vertical decomposition). */

export type DataType = "PRICE" | "SENTIMENT" | "IDENTITY" | "GOVERNANCE";

export type AttestationType = "ZK_PROOF" | "TEE_QUOTE" | "MULTISIG_ORACLE" | "ECDSA_ORACLE";

export type SourceKind = "on-chain" | "off-chain" | "oracle";

export interface OffChainDataPacket {
  source: string;
  dataType: DataType;
  payload: unknown;
  timestamp: number;
  signature: string;
  rawUrl: string;
  attestationType?: AttestationType;
}

export interface OracleResponse {
  value: bigint;
  timestamp: number;
  signature: string;
  provider: string;
  blockNumber?: number;
}

export interface OracleParams {
  feedId: string;
  maxStaleness: number;
  fallbackProviders: string[];
  timeoutMs: number;
}

export interface DataSourceSample {
  id: string;
  kind: SourceKind;
  value: bigint;
  timestamp: number;
  /** 0–1 confidence prior to aggregation */
  confidence: number;
  operator: string;
}

export interface AggregatedNumeric {
  value: bigint;
  /** 0–10000 basis points, aligned with on-chain `IDataOracle` */
  confidenceBps: number;
  /** 0–10000 basis points freshness */
  freshnessBps: number;
  sourceCount: number;
  suspectSources: string[];
  method: "median" | "trimmed_mean" | "consensus_threshold";
}

export interface OnChainMetricsView {
  proposalId: bigint;
  voterTurnoutBps: bigint;
  totalVoiceCreditsUsed: bigint;
  treasuryInflow: bigint;
  treasuryOutflow: bigint;
  tokenPriceUsd: bigint;
  timestamp: number;
  blockHash: string;
}

export interface Layer3Input {
  metadata: {
    batchId: string;
    timestamp: number;
    blockNumber: number;
    merkleRoot: string;
  };
  onChain: OnChainMetricsView;
  offChain: {
    tokenPriceUsd: number;
    marketVolatility: number;
    sentimentScore?: number;
  };
  provenance: {
    signatures: string[];
    sources: string[];
    consensusMethod: string;
    attestationTypes: string[];
  };
}

export type Layer4Event =
  | { type: "RAW_DATA_ARRIVED"; payload: OffChainDataPacket; source: string }
  | { type: "VERIFICATION_PASSED"; payload: DataSourceSample; hash: string }
  | { type: "VERIFICATION_FAILED"; payload: { sourceId: string }; reason: string }
  | { type: "AGGREGATION_COMPLETE"; payload: AggregatedNumeric; method: string }
  | { type: "SCHEMA_READY"; payload: Layer3Input; epoch: number }
  | { type: "AUDIT_ANCHORED"; payload: string; txHash: string };

export interface ProvenanceRecord {
  recordId: string;
  timestamp: number;
  operation: "FETCH" | "VERIFY" | "AGGREGATE" | "NORMALIZE" | "COMMIT";
  inputHashes: string[];
  outputHash: string;
  operatorModule: string;
  blockAnchor?: number;
}

/** Merkle leaf preimage — must match `Layer4MetricEncoding.leafHash` (six fields only). */
export interface MetricLeafPreimage {
  metricId: string;
  value: bigint;
  confidenceScore: bigint;
  freshnessScore: bigint;
  blockHeight: bigint;
  sourceCount: bigint;
}
