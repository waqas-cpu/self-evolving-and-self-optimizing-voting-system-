// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Layer3KPILib} from "./Layer3KPILib.sol";
import {Layer3Constants} from "./Layer3Constants.sol";

/// @notice GATE 3 — deterministic bounded recommendations + confidence (WAD). Conservative fallback encoded by zero deltas.
library Layer3OptimizationLib {
    struct ParameterSetWad {
        uint256 quorumThresholdWad;
        uint256 votingDurationBlocks;
        uint256 voiceCreditRegenerationRate;
        uint256 proposalDepositAmount;
        uint256 dynamicQuorumMultiplierWad;
    }

    struct OptimizationResult {
        ParameterSetWad proposed;
        uint256 confidenceWad;
        bool conservativeFallback;
    }

    function optimize(Layer3KPILib.KPIMetrics memory kpi, ParameterSetWad memory current)
        internal
        pure
        returns (OptimizationResult memory r)
    {
        r.proposed.quorumThresholdWad = current.quorumThresholdWad;
        r.proposed.votingDurationBlocks = current.votingDurationBlocks;
        r.proposed.voiceCreditRegenerationRate = current.voiceCreditRegenerationRate;
        r.proposed.proposalDepositAmount = current.proposalDepositAmount;
        r.proposed.dynamicQuorumMultiplierWad = current.dynamicQuorumMultiplierWad;
        uint256 confidence = Layer3Constants.WAD;

        if (kpi.voterApathyWad > Layer3Constants.WAD / 2) {
            uint256 dq = _min(
                current.quorumThresholdWad - Layer3Constants.QUORUM_MIN_WAD,
                Layer3Constants.QUORUM_MAX_DELTA_WAD / 4
            );
            r.proposed.quorumThresholdWad = current.quorumThresholdWad - dq;
            r.proposed.voiceCreditRegenerationRate = _minUint(
                current.voiceCreditRegenerationRate + 2,
                current.voiceCreditRegenerationRate + Layer3Constants.CREDIT_REGEN_MAX_DELTA
            );
            // 0.85 WAD baseline for apathy-driven moves (explicit WAD math avoids literal scaling mistakes).
            confidence = _min(confidence, (Layer3Constants.WAD * 85) / 100 + dq / 10);
        }

        if (kpi.proposalSuccessRateWad < (2 * Layer3Constants.WAD) / 10) {
            uint256 depDrop =
                _minUint(200, r.proposed.proposalDepositAmount - Layer3Constants.DEPOSIT_MIN);
            r.proposed.proposalDepositAmount = r.proposed.proposalDepositAmount - depDrop;
            uint256 dqmDrop = _min(
                r.proposed.dynamicQuorumMultiplierWad - Layer3Constants.DQM_MIN_WAD,
                Layer3Constants.DQM_MAX_DELTA_WAD / 2
            );
            r.proposed.dynamicQuorumMultiplierWad = r.proposed.dynamicQuorumMultiplierWad - dqmDrop;
            confidence = _min(confidence, (Layer3Constants.WAD * 80) / 100);
        }

        if (kpi.treasuryImpactVelocityWad > (7 * Layer3Constants.WAD) / 10) {
            uint256 bump = _minUint(2000, Layer3Constants.VOTING_DUR_MAX_DELTA / 2);
            r.proposed.votingDurationBlocks =
                _minUint(Layer3Constants.VOTING_DUR_MAX, r.proposed.votingDurationBlocks + bump);
            confidence = _min(confidence, (Layer3Constants.WAD * 82) / 100);
        }

        if (kpi.quadraticEfficiencyWad < (5 * Layer3Constants.WAD) / 10) {
            uint256 up = _min(
                Layer3Constants.DQM_MAX_WAD - r.proposed.dynamicQuorumMultiplierWad,
                Layer3Constants.DQM_MAX_DELTA_WAD / 4
            );
            r.proposed.dynamicQuorumMultiplierWad = r.proposed.dynamicQuorumMultiplierWad + up;
            confidence = _min(confidence, (Layer3Constants.WAD * 78) / 100);
        }

        r.proposed.quorumThresholdWad = _clampWad(
            r.proposed.quorumThresholdWad,
            Layer3Constants.QUORUM_MIN_WAD,
            Layer3Constants.QUORUM_MAX_WAD
        );
        r.proposed.votingDurationBlocks = _clampUint(
            r.proposed.votingDurationBlocks,
            Layer3Constants.VOTING_DUR_MIN,
            Layer3Constants.VOTING_DUR_MAX
        );
        r.proposed.voiceCreditRegenerationRate = _clampUint(
            r.proposed.voiceCreditRegenerationRate,
            Layer3Constants.CREDIT_REGEN_MIN,
            Layer3Constants.CREDIT_REGEN_MAX
        );
        r.proposed.proposalDepositAmount = _clampUint(
            r.proposed.proposalDepositAmount,
            Layer3Constants.DEPOSIT_MIN,
            Layer3Constants.DEPOSIT_MAX
        );
        r.proposed.dynamicQuorumMultiplierWad = _clampWad(
            r.proposed.dynamicQuorumMultiplierWad,
            Layer3Constants.DQM_MIN_WAD,
            Layer3Constants.DQM_MAX_WAD
        );

        if (confidence > Layer3Constants.WAD) confidence = Layer3Constants.WAD;
        r.confidenceWad = confidence;
        if (confidence < Layer3Constants.MIN_CONFIDENCE_WAD) {
            r.conservativeFallback = true;
            r.proposed.quorumThresholdWad = current.quorumThresholdWad;
            r.proposed.votingDurationBlocks = current.votingDurationBlocks;
            r.proposed.voiceCreditRegenerationRate = current.voiceCreditRegenerationRate;
            r.proposed.proposalDepositAmount = current.proposalDepositAmount;
            r.proposed.dynamicQuorumMultiplierWad = current.dynamicQuorumMultiplierWad;
            r.confidenceWad = confidence;
            return r;
        }
        if (_equals(r.proposed, current)) {
            r.conservativeFallback = true;
            r.confidenceWad = Layer3Constants.WAD;
            return r;
        }
    }

    function defaults() internal pure returns (ParameterSetWad memory p) {
        p.quorumThresholdWad = Layer3Constants.QUORUM_DEFAULT_WAD;
        p.votingDurationBlocks = Layer3Constants.VOTING_DUR_DEFAULT;
        p.voiceCreditRegenerationRate = Layer3Constants.CREDIT_REGEN_DEFAULT;
        p.proposalDepositAmount = Layer3Constants.DEPOSIT_DEFAULT;
        p.dynamicQuorumMultiplierWad = Layer3Constants.DQM_DEFAULT_WAD;
    }

    function _equals(ParameterSetWad memory a, ParameterSetWad memory b)
        private
        pure
        returns (bool)
    {
        return a.quorumThresholdWad == b.quorumThresholdWad
            && a.votingDurationBlocks == b.votingDurationBlocks
            && a.voiceCreditRegenerationRate == b.voiceCreditRegenerationRate
            && a.proposalDepositAmount == b.proposalDepositAmount
            && a.dynamicQuorumMultiplierWad == b.dynamicQuorumMultiplierWad;
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    function _minUint(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    function _clampWad(uint256 x, uint256 lo, uint256 hi) private pure returns (uint256) {
        if (x < lo) return lo;
        if (x > hi) return hi;
        return x;
    }

    function _clampUint(uint256 x, uint256 lo, uint256 hi) private pure returns (uint256) {
        if (x < lo) return lo;
        if (x > hi) return hi;
        return x;
    }
}
