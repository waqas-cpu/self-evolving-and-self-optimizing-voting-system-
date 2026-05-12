import { FRESHNESS_RULES } from "../config/freshness.js";
import { AGGREGATION_CONFIG } from "../config/aggregation.config.js";
import { runConsensus } from "./ConsensusEngine.js";
import { Layer4EventBus } from "../bus/Layer4EventBus.js";
import { AuditLogger } from "../buffer/AuditLogger.js";
import type { DataSourceSample, Layer3Input, OffChainDataPacket } from "../types/index.js";
import { NormalizationEngine } from "../normalizer/NormalizationEngine.js";
import { keccak256, toUtf8Bytes } from "ethers";

export interface AggregatorDeps {
  bus: Layer4EventBus;
  audit: AuditLogger;
  normalizer: NormalizationEngine;
}

/**
 * Module 4D — orchestrates verify → consensus → normalize (on-chain commit left to `CommitService`).
 */
export class Aggregator {
  constructor(private readonly deps: AggregatorDeps) {}

  ingestRawPacket(packet: OffChainDataPacket, source: string): void {
    this.deps.bus.emit({ type: "RAW_DATA_ARRIVED", payload: packet, source });
    this.deps.audit.append({
      recordId: keccak256(toUtf8Bytes(`${source}:${packet.timestamp}`)),
      timestamp: Date.now(),
      operation: "FETCH",
      inputHashes: [keccak256(toUtf8Bytes(JSON.stringify(packet)))],
      outputHash: keccak256(toUtf8Bytes("raw")),
      operatorModule: "Aggregator",
    });
  }

  runNumericConsensus(samples: DataSourceSample[], metric: keyof typeof FRESHNESS_RULES): ReturnType<typeof runConsensus> {
    const now = Math.floor(Date.now() / 1000);
    const out = runConsensus({
      samples,
      nowSec: now,
      maxDataAgeSec: FRESHNESS_RULES[metric],
      method: AGGREGATION_CONFIG.DEFAULT_METHOD,
    });
    if (out.ok && out.aggregate) {
      this.deps.bus.emit({ type: "AGGREGATION_COMPLETE", payload: out.aggregate, method: out.aggregate.method });
      this.deps.audit.append({
        recordId: keccak256(toUtf8Bytes(`agg:${now}:${metric}`)),
        timestamp: Date.now(),
        operation: "AGGREGATE",
        inputHashes: samples.map((s) => keccak256(toUtf8Bytes(s.id + s.value.toString()))),
        outputHash: keccak256(toUtf8Bytes(out.aggregate.value.toString())),
        operatorModule: "ConsensusEngine",
      });
    }
    return out;
  }

  buildLayer3Input(params: {
    batchId: string;
    blockNumber: number;
    merkleRoot: string;
    onChain: Layer3Input["onChain"];
    offChainTokenUsd: number;
    offChainVol: number;
    sentiment?: number;
    signatures: string[];
    sources: string[];
  }): Layer3Input {
    const input = this.deps.normalizer.normalize({
      metadata: {
        batchId: params.batchId,
        timestamp: Date.now(),
        blockNumber: params.blockNumber,
        merkleRoot: params.merkleRoot,
      },
      onChain: params.onChain,
      offChain: {
        tokenPriceUsd: params.offChainTokenUsd,
        marketVolatility: params.offChainVol,
        sentimentScore: params.sentiment,
      },
      provenance: {
        signatures: params.signatures,
        sources: params.sources,
        consensusMethod: AGGREGATION_CONFIG.DEFAULT_METHOD,
        attestationTypes: ["ECDSA_ORACLE"],
      },
    });
    this.deps.bus.emit({ type: "SCHEMA_READY", payload: input, epoch: params.blockNumber });
    this.deps.audit.append({
      recordId: keccak256(toUtf8Bytes(`norm:${params.batchId}`)),
      timestamp: Date.now(),
      operation: "NORMALIZE",
      inputHashes: [params.merkleRoot],
      outputHash: keccak256(toUtf8Bytes(JSON.stringify(input.metadata))),
      operatorModule: "NormalizationEngine",
    });
    return input;
  }
}
