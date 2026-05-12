import { keccak256, solidityPacked, AbiCoder } from "ethers";
import type { MetricLeafPreimage } from "../types/index.js";

function sortedPair(a: string, b: string): string {
  const aa = a.toLowerCase();
  const bb = b.toLowerCase();
  const [x, y] = aa < bb ? [a, b] : [b, a];
  return keccak256(solidityPacked(["bytes32", "bytes32"], [x, y]));
}

/** Same preimage as `Layer4MetricEncoding.leafHash` on-chain. */
export function metricLeafHash(m: MetricLeafPreimage): string {
  const coder = AbiCoder.defaultAbiCoder();
  const encoded = coder.encode(
    ["bytes32", "uint256", "uint256", "uint256", "uint256", "uint256"],
    [m.metricId, m.value, m.confidenceScore, m.freshnessScore, m.blockHeight, m.sourceCount]
  );
  return keccak256(encoded);
}

function padPowerOfTwo(leaves: string[]): string[] {
  if (leaves.length === 0) throw new Error("empty leaves");
  let n = leaves.length;
  const target = 2 ** Math.ceil(Math.log2(n));
  const out = leaves.slice();
  const last = leaves[n - 1];
  while (out.length < target) {
    out.push(last);
  }
  return out;
}

export function buildMerkleRoot(leaves: string[]): string {
  if (leaves.length === 0) throw new Error("empty leaves");
  let level = padPowerOfTwo(leaves.map((x) => x.toLowerCase()));
  while (level.length > 1) {
    const next: string[] = [];
    for (let i = 0; i < level.length; i += 2) {
      next.push(sortedPair(level[i], level[i + 1]));
    }
    level = next;
  }
  return level[0];
}

export function verifyLeaf(root: string, leaf: string, proof: string[]): boolean {
  let computed = leaf.toLowerCase();
  for (const p of proof) {
    computed = sortedPair(computed, p).toLowerCase();
  }
  return computed === root.toLowerCase();
}

export function getProof(leaves: string[], index: number): string[] {
  const padded = padPowerOfTwo(leaves);
  let level = padded.slice();
  const proof: string[] = [];
  let idx = index;
  while (level.length > 1) {
    const sibling = idx % 2 === 0 ? level[idx + 1] : level[idx - 1];
    proof.push(sibling);
    const next: string[] = [];
    for (let i = 0; i < level.length; i += 2) {
      next.push(sortedPair(level[i], level[i + 1]));
    }
    idx = Math.floor(idx / 2);
    level = next;
  }
  return proof;
}
