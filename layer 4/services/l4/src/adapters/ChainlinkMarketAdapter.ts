import { type HDNodeWallet, Wallet, keccak256, toUtf8Bytes } from "ethers";
import { BaseAdapter } from "./BaseAdapter.js";
import type { OracleParams, OracleResponse } from "../types/index.js";
import { attestationDigestHex, recoverAttestationSigner } from "../crypto/SignatureVerifier.js";

/**
 * Mock Chainlink-style feed — production replaces `requestData` with `AggregatorV3Interface.latestRoundData`.
 */
export class ChainlinkMarketAdapter extends BaseAdapter {
  private lastFeedId = "";

  constructor(private readonly oracleWallet: Wallet | HDNodeWallet) {
    super();
  }

  static feedPayloadHash(feedId: string): string {
    return keccak256(toUtf8Bytes(`chainlink:${feedId}`));
  }

  getProviderName(): string {
    return "chainlink";
  }

  async requestData(params: OracleParams): Promise<OracleResponse> {
    this.lastFeedId = params.feedId;
    const now = Math.floor(Date.now() / 1000);
    const ph = ChainlinkMarketAdapter.feedPayloadHash(params.feedId);
    const digestHex = attestationDigestHex(ph, BigInt(now));
    const sig = this.oracleWallet.signingKey.sign(digestHex);
    return {
      value: 3_500_00000000n,
      timestamp: now,
      signature: sig.serialized,
      provider: this.getProviderName(),
      blockNumber: 1,
    };
  }

  verifyOracleSignature(response: OracleResponse): boolean {
    const ph = ChainlinkMarketAdapter.feedPayloadHash(this.lastFeedId);
    const recovered = recoverAttestationSigner(ph, BigInt(response.timestamp), response.signature);
    return recovered.toLowerCase() === this.oracleWallet.address.toLowerCase();
  }
}
