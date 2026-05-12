// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Layer 5 timelock entrypoint — ABI must match `layer 5/contracts/layer5/TimelockController.queueAdjustment`.
interface ILayer5Timelock {
    struct ParameterSet {
        uint256 votingDuration;
        uint256 quorumThreshold;
        uint256 creditRegenRate;
        uint256 maxCreditCap;
        uint256 submissionDelay;
        uint256 proposalThreshold;
    }

    function queueAdjustment(ParameterSet calldata params) external returns (bytes32 id);
}
