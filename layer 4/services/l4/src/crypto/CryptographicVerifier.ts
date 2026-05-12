import { keccak256, toUtf8Bytes } from "ethers";
import { verifyAgainstWhitelist } from "./SignatureVerifier.js";
import { verifyLeaf } from "./MerkleBuilder.js";

export interface VerificationResult {
  isValid: boolean;
  dataHash: string;
  signatureScheme: "ECDSA" | "NONE";
  verifierAddress: string;
  reason?: string;
}

export class CryptographicVerifier {
  verifyMerkleProof(root: string, leaf: string, proof: string[]): VerificationResult {
    const ok = verifyLeaf(root, leaf, proof);
    return {
      isValid: ok,
      dataHash: leaf,
      signatureScheme: "NONE",
      verifierAddress: "merkle",
      reason: ok ? undefined : "invalid_merkle_proof",
    };
  }

  verifyECDSAAttestation(params: {
    dataPayloadHash: string;
    observedAt: bigint;
    signature: string;
    whitelist: Set<string>;
  }): VerificationResult {
    const r = verifyAgainstWhitelist(
      params.dataPayloadHash,
      params.observedAt,
      params.signature,
      params.whitelist
    );
    const inner = keccak256(
      toUtf8Bytes(`${params.dataPayloadHash}:${params.observedAt.toString()}`)
    );
    return {
      isValid: r.valid,
      dataHash: inner,
      signatureScheme: "ECDSA",
      verifierAddress: "ecdsa",
      reason: r.reason,
    };
  }

  computeDataIntegrityHash(data: unknown): string {
    return keccak256(toUtf8Bytes(JSON.stringify(data)));
  }
}
