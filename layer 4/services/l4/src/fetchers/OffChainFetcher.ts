import type { OffChainDataPacket } from "../types/index.js";

export interface FetcherOpts {
  timeoutMs: number;
  maxBytes: number;
}

const defaultOpts: FetcherOpts = { timeoutMs: 8_000, maxBytes: 1_000_000 };

/**
 * HTTPS client wrapper with timeout budget (horizontal Off-Chain Fetcher module).
 */
export class OffChainFetcher {
  constructor(private readonly opts: FetcherOpts = defaultOpts) {}

  async fetchJson(url: string, init?: RequestInit): Promise<unknown> {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), this.opts.timeoutMs);
    try {
      const res = await fetch(url, { ...init, signal: ctrl.signal });
      if (!res.ok) throw new Error(`http_${res.status}`);
      const buf = await res.arrayBuffer();
      if (buf.byteLength > this.opts.maxBytes) throw new Error("response_too_large");
      const text = new TextDecoder().decode(buf);
      return JSON.parse(text) as unknown;
    } finally {
      clearTimeout(t);
    }
  }

  toPacket(source: string, dataType: OffChainDataPacket["dataType"], payload: unknown, signature: string, rawUrl: string): OffChainDataPacket {
    return {
      source,
      dataType,
      payload,
      timestamp: Math.floor(Date.now() / 1000),
      signature,
      rawUrl,
    };
  }
}
