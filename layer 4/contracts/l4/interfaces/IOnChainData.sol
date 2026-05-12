// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Module 4A — on-chain metrics surface for Layer 4 collectors (read-only composition).
interface IOnChainData {
    struct OnChainMetrics {
        uint256 proposalId;
        uint256 voterTurnoutBps;
        uint256 totalVoiceCreditsUsed;
        uint256 treasuryInflow;
        uint256 treasuryOutflow;
        uint256 tokenPriceUsd;
        uint256 timestamp;
        bytes32 blockHash;
    }

    function getMetrics(uint256 proposalId) external view returns (OnChainMetrics memory);
}
