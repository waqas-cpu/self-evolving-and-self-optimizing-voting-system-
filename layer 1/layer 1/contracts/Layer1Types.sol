// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Layer1Types {
    enum IdentityState {
        NONE,
        ENROLLED,
        ACTIVE,
        FLAGGED,
        REVOKED
    }

    struct EnrollmentRequest {
        bytes32 didHash;
        bytes32 biometricNullifier;
        bytes32 deviceFingerprint;
        uint64 timestamp;
        uint16 reputationBps;
        bytes32[] providerNullifiers;
        bytes zkProof;
    }

    struct IdentityRecord {
        bytes32 didHash;
        bytes32 uniqueNullifier;
        Layer1Types.IdentityState state;
        uint64 enrolledBlock;
        uint64 expiryBlock;
    }
}
