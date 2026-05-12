// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Layer3OptimizationLib} from "./Layer3OptimizationLib.sol";
import {Layer3Constants} from "./Layer3Constants.sol";

/// @notice GATE 4 — absolute bounds, per-epoch deltas, safety quorum floor, cumulative reduction ceiling.
library Layer3SafetyLib {
    /// @notice Governance capture mitigation: quorum cannot fall below 0.10.
    uint256 internal constant MIN_SAFETY_QUORUM_WAD = 1e17;

    enum Violation {
        NONE,
        BOUNDS,
        DELTA_QUORUM,
        DELTA_DURATION,
        DELTA_REGEN,
        DELTA_DEPOSIT,
        DELTA_DQM,
        CUMULATIVE_QUORUM,
        SAFETY_QUORUM_FLOOR
    }

    struct CumulativeState {
        uint256 quorumReductionSumWad;
    }

    function enforce(
        Layer3OptimizationLib.ParameterSetWad memory current,
        Layer3OptimizationLib.ParameterSetWad memory proposed,
        CumulativeState memory cum
    ) internal pure returns (bool ok, Violation v) {
        if (!_inWadBounds(proposed)) return (false, Violation.BOUNDS);
        if (!_inUintBounds(proposed)) return (false, Violation.BOUNDS);
        if (proposed.quorumThresholdWad < MIN_SAFETY_QUORUM_WAD) {
            return (false, Violation.SAFETY_QUORUM_FLOOR);
        }

        if (!_deltaQuorumOk(current.quorumThresholdWad, proposed.quorumThresholdWad)) {
            return (false, Violation.DELTA_QUORUM);
        }
        if (
            !_deltaUintOk(
                current.votingDurationBlocks,
                proposed.votingDurationBlocks,
                Layer3Constants.VOTING_DUR_MAX_DELTA
            )
        ) {
            return (false, Violation.DELTA_DURATION);
        }
        if (
            !_deltaUintOk(
                current.voiceCreditRegenerationRate,
                proposed.voiceCreditRegenerationRate,
                Layer3Constants.CREDIT_REGEN_MAX_DELTA
            )
        ) {
            return (false, Violation.DELTA_REGEN);
        }
        if (
            !_deltaUintOk(
                current.proposalDepositAmount,
                proposed.proposalDepositAmount,
                Layer3Constants.DEPOSIT_MAX_DELTA
            )
        ) {
            return (false, Violation.DELTA_DEPOSIT);
        }
        if (
            !_deltaWadOk(
                current.dynamicQuorumMultiplierWad,
                proposed.dynamicQuorumMultiplierWad,
                Layer3Constants.DQM_MAX_DELTA_WAD
            )
        ) {
            return (false, Violation.DELTA_DQM);
        }

        uint256 reduction = 0;
        if (proposed.quorumThresholdWad < current.quorumThresholdWad) {
            reduction = current.quorumThresholdWad - proposed.quorumThresholdWad;
        }
        if (cum.quorumReductionSumWad + reduction > 3e17) {
            return (false, Violation.CUMULATIVE_QUORUM);
        }

        return (true, Violation.NONE);
    }

    function _inWadBounds(Layer3OptimizationLib.ParameterSetWad memory p)
        private
        pure
        returns (bool)
    {
        if (
            p.quorumThresholdWad < Layer3Constants.QUORUM_MIN_WAD
                || p.quorumThresholdWad > Layer3Constants.QUORUM_MAX_WAD
        ) {
            return false;
        }
        if (
            p.dynamicQuorumMultiplierWad < Layer3Constants.DQM_MIN_WAD
                || p.dynamicQuorumMultiplierWad > Layer3Constants.DQM_MAX_WAD
        ) {
            return false;
        }
        return true;
    }

    function _inUintBounds(Layer3OptimizationLib.ParameterSetWad memory p)
        private
        pure
        returns (bool)
    {
        if (
            p.votingDurationBlocks < Layer3Constants.VOTING_DUR_MIN
                || p.votingDurationBlocks > Layer3Constants.VOTING_DUR_MAX
        ) {
            return false;
        }
        if (
            p.voiceCreditRegenerationRate < Layer3Constants.CREDIT_REGEN_MIN
                || p.voiceCreditRegenerationRate > Layer3Constants.CREDIT_REGEN_MAX
        ) {
            return false;
        }
        if (
            p.proposalDepositAmount < Layer3Constants.DEPOSIT_MIN
                || p.proposalDepositAmount > Layer3Constants.DEPOSIT_MAX
        ) {
            return false;
        }
        return true;
    }

    function _deltaQuorumOk(uint256 beforeWad, uint256 afterWad) private pure returns (bool) {
        uint256 d = beforeWad > afterWad ? beforeWad - afterWad : afterWad - beforeWad;
        return d <= Layer3Constants.QUORUM_MAX_DELTA_WAD;
    }

    function _deltaUintOk(uint256 beforeV, uint256 afterV, uint256 maxDelta)
        private
        pure
        returns (bool)
    {
        uint256 d = beforeV > afterV ? beforeV - afterV : afterV - beforeV;
        return d <= maxDelta;
    }

    function _deltaWadOk(uint256 beforeW, uint256 afterW, uint256 maxDeltaWad)
        private
        pure
        returns (bool)
    {
        uint256 d = beforeW > afterW ? beforeW - afterW : afterW - beforeW;
        return d <= maxDeltaWad;
    }
}
