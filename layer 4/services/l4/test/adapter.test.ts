import { describe, expect, it } from "@jest/globals";
import { Wallet } from "ethers";
import { ChainlinkMarketAdapter } from "../src/adapters/ChainlinkMarketAdapter.js";

describe("ChainlinkMarketAdapter", () => {
  it("signs responses verifiable by adapter", async () => {
    const w = Wallet.createRandom();
    const a = new ChainlinkMarketAdapter(w);
    const r = await a.requestData({
      feedId: "eth-usd",
      maxStaleness: 300,
      fallbackProviders: [],
      timeoutMs: 5000,
    });
    expect(a.verifyOracleSignature(r)).toBe(true);
  });
});
