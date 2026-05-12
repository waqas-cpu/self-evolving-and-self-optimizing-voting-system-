// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal read/write surface of Layer 2 `ParameterRegistry` for Layer 3 orchestration.
interface ILayer2ParameterRegistry {
    enum ParamKey {
        VOTING_DURATION,
        QUORUM_THRESHOLD,
        CREDIT_REGEN_RATE,
        MAX_CREDIT_CAP,
        SUBMISSION_DELAY,
        PROPOSAL_THRESHOLD
    }

    function bounds(ParamKey key) external view returns (uint256 min, uint256 max);

    function values(ParamKey key) external view returns (uint256);

    function proposeParameterAdjustment(
        ParamKey key,
        uint256 newValue,
        bytes calldata data,
        bytes32 justificationHash
    ) external returns (bytes32 adjustmentId, uint256 effectiveBlock);
}
