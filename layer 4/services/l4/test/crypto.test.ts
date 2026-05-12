import { describe, expect, it } from "@jest/globals";
import { Wallet, keccak256, toUtf8Bytes } from "ethers";
import { attestationDigestHex, recoverAttestationSigner, verifyOracleSignature } from "../src/crypto/SignatureVerifier.js";

describe("SignatureVerifier", () => {
  it("round-trips oracle attestation digest", () => {
    const w = Wallet.createRandom();
    const payloadHash = keccak256(toUtf8Bytes("payload"));
    const observedAt = 12345n;
    const digestHex = attestationDigestHex(payloadHash, observedAt);
    const sig = w.signingKey.sign(digestHex);
    const recovered = recoverAttestationSigner(payloadHash, observedAt, sig.serialized);
    expect(recovered.toLowerCase()).toBe(w.address.toLowerCase());
    const v = verifyOracleSignature({
      dataPayloadHash: payloadHash,
      observedAt,
      signature: sig.serialized,
      expectedSigner: w.address,
    });
    expect(v.valid).toBe(true);
  });
});
