import { type HDNodeWallet, keccak256, toUtf8Bytes, Wallet } from "ethers";
import { BaseAdapter } from "./BaseAdapter.js";
import type { OracleParams, OracleResponse } from "../types/index.js";
import { attestationDigestHex, recoverAttestationSigner } from "../crypto/SignatureVerifier.js";

/** Off-chain sentiment stub — Gate L4-08 requires attestation metadata on real deployments. */
export class SentimentAdapter extends BaseAdapter {
  private lastFeedId = "";

  constructor(private readonly oracleWallet: Wallet | HDNodeWallet) {
    super();
  }

  static sentimentPayloadHash(feedId: string): string {
    return keccak256(toUtf8Bytes(`sentiment:${feedId}`));
  }

  getProviderName(): string {
    return "sentiment-rest";
  }

  async requestData(params: OracleParams): Promise<OracleResponse> {
    this.lastFeedId = params.feedId;
    const now = Math.floor(Date.now() / 1000);
    const ph = SentimentAdapter.sentimentPayloadHash(params.feedId);
    const digestHex = attestationDigestHex(ph, BigInt(now));
    const sig = this.oracleWallet.signingKey.sign(digestHex);
    return {
      value: 65n,
      timestamp: now,
      signature: sig.serialized,
      provider: this.getProviderName(),
    };
  }

  verifyOracleSignature(response: OracleResponse): boolean {
    const ph = SentimentAdapter.sentimentPayloadHash(this.lastFeedId);
    const recovered = recoverAttestationSigner(ph, BigInt(response.timestamp), response.signature);
    return recovered.toLowerCase() === this.oracleWallet.address.toLowerCase();
  }
}
