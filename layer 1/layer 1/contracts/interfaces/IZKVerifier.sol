// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IZKVerifier {
    function verifyEnrollmentProof(bytes calldata proof, bytes32[] calldata publicInputs) external view returns (bool);

    function verifyBindingProof(bytes calldata proof, bytes32[] calldata publicInputs) external view returns (bool);
}
