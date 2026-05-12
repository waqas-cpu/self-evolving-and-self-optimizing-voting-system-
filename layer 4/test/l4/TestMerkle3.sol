// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDataOracle} from "../../contracts/l4/interfaces/IDataOracle.sol";
import {Layer4MetricEncoding} from "../../contracts/l4/Layer4MetricEncoding.sol";

/// @dev Fixed 3-leaf Merkle layout: (l0,l1), (l2,l2) → root (matches `MerkleBuilder` in services).
library TestMerkle3 {
    function pair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function tree(IDataOracle.AggregatedMetric[3] memory m)
        internal
        pure
        returns (bytes32 root, bytes32[3] memory leaves, bytes32[][] memory proofs)
    {
        leaves[0] = Layer4MetricEncoding.leafHash(m[0]);
        leaves[1] = Layer4MetricEncoding.leafHash(m[1]);
        leaves[2] = Layer4MetricEncoding.leafHash(m[2]);
        bytes32 p01 = pair(leaves[0], leaves[1]);
        bytes32 p22 = pair(leaves[2], leaves[2]);
        root = pair(p01, p22);

        proofs = new bytes32[][](3);
        proofs[0] = new bytes32[](2);
        proofs[0][0] = leaves[1];
        proofs[0][1] = p22;
        proofs[1] = new bytes32[](2);
        proofs[1][0] = leaves[0];
        proofs[1][1] = p22;
        proofs[2] = new bytes32[](2);
        proofs[2][0] = leaves[2];
        proofs[2][1] = p01;
    }
}
