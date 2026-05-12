import { describe, expect, it } from "@jest/globals";
import { Layer4EventBus } from "../src/bus/Layer4EventBus.js";

describe("Layer4EventBus", () => {
  it("delivers typed events", () => {
    const bus = new Layer4EventBus();
    let seen = 0;
    const off = bus.on("AGGREGATION_COMPLETE", () => {
      seen += 1;
    });
    bus.emit({
      type: "AGGREGATION_COMPLETE",
      payload: {
        value: 1n,
        confidenceBps: 8000,
        freshnessBps: 9000,
        sourceCount: 3,
        suspectSources: [],
        method: "median",
      },
      method: "median",
    });
    expect(seen).toBe(1);
    off();
    bus.emit({
      type: "AGGREGATION_COMPLETE",
      payload: {
        value: 1n,
        confidenceBps: 8000,
        freshnessBps: 9000,
        sourceCount: 3,
        suspectSources: [],
        method: "median",
      },
      method: "median",
    });
    expect(seen).toBe(1);
  });
});
