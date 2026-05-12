import { AGGREGATION_CONFIG } from "../config/aggregation.config.js";
import type { Layer3Input } from "../types/index.js";
import { validateLayer3Input } from "./Validators.js";

/**
 * Module 4E / horizontal Schema Engine — Gate L4-08 caps off-chain influence at 20%.
 */
export class NormalizationEngine {
  normalize(input: Layer3Input): Layer3Input {
    const cap = AGGREGATION_CONFIG.OFF_CHAIN_MAX_WEIGHT;
    const oc = { ...input.offChain };
    if (oc.sentimentScore !== undefined) {
      oc.sentimentScore = Math.min(oc.sentimentScore, cap);
    }
    oc.marketVolatility = Math.min(oc.marketVolatility, cap);
    const out: Layer3Input = {
      ...input,
      offChain: oc,
    };
    const v = validateLayer3Input(out);
    if (!v.valid) {
      throw new Error(`Layer3Input invalid: ${v.errors.join(",")}`);
    }
    return out;
  }
}
