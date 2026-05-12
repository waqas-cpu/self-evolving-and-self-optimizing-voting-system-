// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Layer3KPILib} from "./Layer3KPILib.sol";
import {Layer3OptimizationLib} from "./Layer3OptimizationLib.sol";

/// @notice Agent 4 — deterministic circuit breaker before safety hardening.
library Layer3SimulationLib {
    uint256 internal constant WAD = 1e18;

    error SimulationFailed();

    function requirePass(
        Layer3KPILib.KPIMetrics memory beforeKpi,
        Layer3OptimizationLib.ParameterSetWad memory current,
        Layer3OptimizationLib.OptimizationResult memory opt,
        bytes32 modelVersionId
    ) internal pure returns (bytes32 reportHash) {
        if (opt.conservativeFallback) {
            return keccak256(abi.encodePacked("SIM_SKIP", modelVersionId));
        }
        uint256 stress = _absDiffWad(opt.proposed.quorumThresholdWad, current.quorumThresholdWad);
        stress += _absDiffUint(opt.proposed.votingDurationBlocks, current.votingDurationBlocks)
            * WAD / 10_000;
        if (stress > WAD / 2 && opt.confidenceWad < 88e16) revert SimulationFailed();
        if (
            opt.proposed.quorumThresholdWad < 6e17 && beforeKpi.voterApathyWad > 8e17
                && opt.confidenceWad < 75e16
        ) {
            revert SimulationFailed();
        }
        reportHash = keccak256(
            abi.encode(
                beforeKpi.voterApathyWad,
                beforeKpi.proposalSuccessRateWad,
                opt.proposed.quorumThresholdWad,
                opt.proposed.votingDurationBlocks,
                opt.confidenceWad,
                modelVersionId
            )
        );
    }

    function _absDiffWad(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _absDiffUint(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}
