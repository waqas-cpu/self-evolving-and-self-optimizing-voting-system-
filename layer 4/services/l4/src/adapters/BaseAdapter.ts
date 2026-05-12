import type { OracleParams, OracleResponse } from "../types/index.js";

export abstract class BaseAdapter {
  abstract getProviderName(): string;

  abstract requestData(params: OracleParams): Promise<OracleResponse>;

  abstract verifyOracleSignature(response: OracleResponse): boolean;
}
