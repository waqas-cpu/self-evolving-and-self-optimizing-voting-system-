// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal read surface for DAO governance metrics (Layer 2 or indexer contracts).
interface IGovernanceViews {
    function voterTurnoutBps(uint256 proposalId) external view returns (uint256);

    function totalVoiceCreditsUsed(uint256 proposalId) external view returns (uint256);
}

interface ITreasuryViews {
    function flowsForProposal(uint256 proposalId)
        external
        view
        returns (uint256 inflow, uint256 outflow);
}

interface ITokenPriceViews {
    /// @return priceUsd8 Token price in USD with 8 decimals (vertical decomposition convention).
    function latestPriceUsd8() external view returns (uint256);
}
