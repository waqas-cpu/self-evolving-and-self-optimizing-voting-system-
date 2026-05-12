import { keccak256, toUtf8Bytes } from "ethers";
import type { ProvenanceRecord } from "../types/index.js";

/**
 * Module 4F / horizontal audit — append-only provenance (WORM in-process; mirror to IPFS in ops).
 */
export class AuditLogger {
  private readonly records: ProvenanceRecord[] = [];

  append(r: ProvenanceRecord): void {
    this.records.push(r);
  }

  getRecords(): readonly ProvenanceRecord[] {
    return this.records;
  }

  merkleRootEpoch(): string {
    if (this.records.length === 0) {
      return keccak256(toUtf8Bytes("empty"));
    }
    return keccak256(toUtf8Bytes(this.records.map((x) => x.outputHash).join("")));
  }

  verifyIntegrity(recordId: string): boolean {
    return this.records.some((r) => r.recordId === recordId);
  }
}
