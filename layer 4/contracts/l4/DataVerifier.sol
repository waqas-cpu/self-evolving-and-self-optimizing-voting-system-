// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Module 4C — Merkle proof verification for batched attestations (keccak pair ordering).
library DataVerifier {
    error InvalidProof();

    function verifyLeaf(bytes32 root, bytes32 leaf, bytes32[] calldata proof)
        internal
        pure
        returns (bool)
    {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            computedHash = _hashPair(computedHash, proofElement);
        }
        return computedHash == root;
    }

    function requireLeaf(bytes32 root, bytes32 leaf, bytes32[] calldata proof) internal pure {
        if (!verifyLeaf(root, leaf, proof)) revert InvalidProof();
    }

    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? _efficientHash(a, b) : _efficientHash(b, a);
    }

    function _efficientHash(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }
}
