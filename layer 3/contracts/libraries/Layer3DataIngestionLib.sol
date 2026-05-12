// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice GATE 1 — deterministic multi-oracle validation (≥3 distinct trusted signers).
library Layer3DataIngestionLib {
    uint256 internal constant MIN_SOURCES = 3;
    /// @notice On-chain observation freshness (spec: < 1 hour).
    uint256 internal constant MAX_ONCHAIN_DATA_AGE = 1 hours;
    /// @notice Off-chain bundle freshness (spec: < 24 hours).
    uint256 internal constant MAX_OFFCHAIN_DATA_AGE = 24 hours;

    error Gate1InsufficientSources();
    error Gate1UntrustedOracle();
    error Gate1DuplicateOracle();
    error Gate1StaleOnChain();
    error Gate1StaleOffChain();
    error Gate1BadSignature();

    struct Attestation {
        address oracle;
        uint256 observedAt;
        bytes32 payloadHash;
        bytes signature;
    }

    /// @return frameHash Commitment to validated payload for downstream gates.
    /// @return anomalyFlag Z-score analogue: large deviation vs simple baseline triggers review flag (does not revert).
    function validateFrame(
        mapping(address => bool) storage oracleWhitelist,
        bytes32 dataPayloadHash,
        uint256 onChainReferenceTime,
        uint256 offChainReferenceTime,
        Attestation[3] calldata sigs
    ) internal view returns (bytes32 frameHash, bool anomalyFlag) {
        if (
            block.timestamp < onChainReferenceTime
                || block.timestamp - onChainReferenceTime > MAX_ONCHAIN_DATA_AGE
        ) {
            revert Gate1StaleOnChain();
        }
        if (
            block.timestamp < offChainReferenceTime
                || block.timestamp - offChainReferenceTime > MAX_OFFCHAIN_DATA_AGE
        ) {
            revert Gate1StaleOffChain();
        }
        address[3] memory seen;
        for (uint256 i = 0; i < MIN_SOURCES; i++) {
            Attestation calldata a = sigs[i];
            if (!oracleWhitelist[a.oracle]) revert Gate1UntrustedOracle();
            if (
                block.timestamp < a.observedAt
                    || block.timestamp - a.observedAt > MAX_OFFCHAIN_DATA_AGE
            ) {
                revert Gate1StaleOffChain();
            }
            for (uint256 j = 0; j < i; j++) {
                if (seen[j] == a.oracle) revert Gate1DuplicateOracle();
            }
            seen[i] = a.oracle;
            if (a.payloadHash != dataPayloadHash) revert Gate1BadSignature();
            bytes32 inner = keccak256(abi.encodePacked(dataPayloadHash, a.observedAt));
            bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", inner));
            address recovered = _recover(digest, a.signature);
            if (recovered != a.oracle) revert Gate1BadSignature();
        }
        frameHash = keccak256(
            abi.encodePacked(dataPayloadHash, onChainReferenceTime, offChainReferenceTime)
        );
        // Deterministic anomaly hint: payload entropy vs zero baseline (placeholder for Z-score pipeline).
        uint256 deviation = uint256(dataPayloadHash) % (1 ether);
        anomalyFlag = deviation > 97 * (1 ether) / 100; // > ~0.97 arbitrary deterministic threshold
    }

    function _recover(bytes32 digest, bytes memory signature) private pure returns (address) {
        if (signature.length != 65) revert Gate1BadSignature();
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        return ecrecover(digest, v, r, s);
    }
}
