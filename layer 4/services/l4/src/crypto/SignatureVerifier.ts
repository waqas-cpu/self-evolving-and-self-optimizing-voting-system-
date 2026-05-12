import { computeAddress, concat, getBytes, keccak256, Signature, SigningKey, solidityPacked, toUtf8Bytes } from "ethers";

export interface VerifyResult {
  valid: boolean;
  reason?: string;
}

/**
 * Gate L4-01 — matches Solidity `Layer3DataIngestionLib` EIP-191 over `keccak256(abi.encodePacked(payloadHash, observedAt))`.
 */
export function attestationDigestHex(dataPayloadHash: string, observedAt: bigint): string {
  const inner = keccak256(solidityPacked(["bytes32", "uint256"], [dataPayloadHash, observedAt]));
  const prefix = toUtf8Bytes("\x19Ethereum Signed Message:\n32");
  return keccak256(concat([prefix, getBytes(inner)]));
}

export function recoverAttestationSigner(
  dataPayloadHash: string,
  observedAt: bigint,
  signature: string
): string {
  const digest = attestationDigestHex(dataPayloadHash, observedAt);
  const sig = Signature.from(signature);
  const pk = SigningKey.recoverPublicKey(getBytes(digest), sig);
  return computeAddress(pk);
}

export function verifyOracleSignature(params: {
  dataPayloadHash: string;
  observedAt: bigint;
  signature: string;
  expectedSigner: string;
}): VerifyResult {
  try {
    const recovered = recoverAttestationSigner(params.dataPayloadHash, params.observedAt, params.signature);
    if (recovered.toLowerCase() !== params.expectedSigner.toLowerCase()) {
      return { valid: false, reason: "signer_mismatch" };
    }
    return { valid: true };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return { valid: false, reason: `bad_signature:${msg}` };
  }
}

export function verifyAgainstWhitelist(
  dataPayloadHash: string,
  observedAt: bigint,
  signature: string,
  whitelist: Set<string>
): VerifyResult {
  try {
    const recovered = recoverAttestationSigner(dataPayloadHash, observedAt, signature);
    if (!whitelist.has(recovered.toLowerCase())) {
      return { valid: false, reason: "not_whitelisted" };
    }
    return { valid: true };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return { valid: false, reason: msg };
  }
}
