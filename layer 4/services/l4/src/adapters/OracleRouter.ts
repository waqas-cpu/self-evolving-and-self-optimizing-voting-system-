import type { OracleParams, OracleResponse } from "../types/index.js";
import type { BaseAdapter } from "./BaseAdapter.js";

/** Routes a feed id to a concrete oracle adapter with simple priority fallback. */
export class OracleRouter {
  constructor(private readonly routes: Map<string, BaseAdapter[]>) {}

  register(feedId: string, adapters: BaseAdapter[]): void {
    this.routes.set(feedId, adapters);
  }

  async request(feedId: string, params: OracleParams): Promise<OracleResponse> {
    const chain = this.routes.get(feedId) ?? [];
    let lastErr: unknown;
    for (const a of chain) {
      try {
        return await a.requestData({ ...params, feedId });
      } catch (e) {
        lastErr = e;
      }
    }
    throw new Error(`all_oracle_adapters_failed:${String(lastErr)}`);
  }
}
