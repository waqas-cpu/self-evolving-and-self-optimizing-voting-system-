// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IZKVerifier} from "../interfaces/IZKVerifier.sol";

contract MockZKVerifier is IZKVerifier {
    bool public enrollmentPass = true;
    bool public bindingPass = true;

    function setEnrollmentPass(bool value) external {
        enrollmentPass = value;
    }

    function setBindingPass(bool value) external {
        bindingPass = value;
    }

    function verifyEnrollmentProof(bytes calldata, bytes32[] calldata) external view returns (bool) {
        return enrollmentPass;
    }

    function verifyBindingProof(bytes calldata, bytes32[] calldata) external view returns (bool) {
        return bindingPass;
    }
}
