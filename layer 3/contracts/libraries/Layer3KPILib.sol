// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice GATE 2 — deterministic KPI math on WAD-fixed inputs (1e18 = 100%).
library Layer3KPILib {
    uint256 internal constant WAD = 1e18;
    /// @notice Spec: minimum 7-day statistical window.
    uint256 internal constant MIN_TIME_WINDOW = 7 days;

    error Gate2TimeWindowTooShort();

    struct RawMetrics {
        uint256 actualVoters;
        uint256 eligibleVoters;
        uint256 passedProposals;
        uint256 totalProposals;
        uint256 actualQuadraticCostWad;
        uint256 theoreticalOptimalCostWad;
        uint256 treasuryOutflowWad;
        uint256 timeWindowWad;
        uint256 creditsSpentWad;
        uint256 creditsAllocatedWad;
    }

    struct KPIMetrics {
        uint256 voterApathyWad;
        uint256 proposalSuccessRateWad;
        uint256 quadraticEfficiencyWad;
        uint256 treasuryImpactVelocityWad;
        uint256 creditUtilizationWad;
        uint256 timestamp;
    }

    function compute(RawMetrics memory m, uint256 timeWindowSecs)
        internal
        view
        returns (KPIMetrics memory k)
    {
        if (timeWindowSecs < MIN_TIME_WINDOW) revert Gate2TimeWindowTooShort();
        k.timestamp = block.timestamp;

        if (m.eligibleVoters == 0) {
            k.voterApathyWad = WAD;
        } else {
            k.voterApathyWad =
                _wadDiv(_wadMul(WAD, m.eligibleVoters - m.actualVoters), m.eligibleVoters);
        }

        if (m.totalProposals == 0) k.proposalSuccessRateWad = 0;
        else k.proposalSuccessRateWad = _wadDiv(_wadMul(WAD, m.passedProposals), m.totalProposals);

        if (m.theoreticalOptimalCostWad == 0) {
            k.quadraticEfficiencyWad = WAD;
        } else {
            k.quadraticEfficiencyWad = _min(
                WAD, _wadDiv(_wadMul(WAD, m.actualQuadraticCostWad), m.theoreticalOptimalCostWad)
            );
        }

        if (m.timeWindowWad == 0) {
            k.treasuryImpactVelocityWad = 0;
        } else {
            k.treasuryImpactVelocityWad =
                _wadDiv(_wadMul(WAD, m.treasuryOutflowWad), m.timeWindowWad);
        }

        if (m.creditsAllocatedWad == 0) {
            k.creditUtilizationWad = 0;
        } else {
            k.creditUtilizationWad = _wadDiv(_wadMul(WAD, m.creditsSpentWad), m.creditsAllocatedWad);
        }

        k.voterApathyWad = _clampWad(k.voterApathyWad);
        k.proposalSuccessRateWad = _clampWad(k.proposalSuccessRateWad);
        k.quadraticEfficiencyWad = _clampWad(k.quadraticEfficiencyWad);
        k.treasuryImpactVelocityWad = _clampWad(k.treasuryImpactVelocityWad);
        k.creditUtilizationWad = _clampWad(k.creditUtilizationWad);
    }

    function _wadMul(uint256 x, uint256 y) private pure returns (uint256) {
        return (x * y) / WAD;
    }

    function _wadDiv(uint256 x, uint256 y) private pure returns (uint256) {
        return (x * WAD) / y;
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    function _clampWad(uint256 x) private pure returns (uint256) {
        if (x > WAD) return WAD;
        return x;
    }
}
