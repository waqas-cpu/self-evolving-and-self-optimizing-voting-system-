import type { Layer4Event } from "../types/index.js";

type Handler = (ev: Layer4Event) => void;

/**
 * Horizontal event bus — typed fan-out between Layer 4 modules.
 */
export class Layer4EventBus {
  private readonly handlers = new Map<Layer4Event["type"], Set<Handler>>();

  on<T extends Layer4Event["type"]>(type: T, fn: Handler): () => void {
    let set = this.handlers.get(type);
    if (!set) {
      set = new Set();
      this.handlers.set(type, set);
    }
    set.add(fn);
    return () => set!.delete(fn);
  }

  emit(ev: Layer4Event): void {
    const set = this.handlers.get(ev.type);
    if (!set) return;
    for (const h of set) {
      h(ev);
    }
  }
}
