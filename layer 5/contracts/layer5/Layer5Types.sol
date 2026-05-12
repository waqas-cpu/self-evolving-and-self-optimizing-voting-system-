// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Layout MUST match `ParameterRegistry.Layer5ParameterSet` (Layer 2).
struct ParameterSet {
    uint256 votingDuration;
    uint256 quorumThreshold;
    uint256 creditRegenRate;
    uint256 maxCreditCap;
    uint256 submissionDelay;
    uint256 proposalThreshold;
}

enum Layer5State {
    DORMANT,
    QUEUED,
    ACTIVE,
    VETOED
}
