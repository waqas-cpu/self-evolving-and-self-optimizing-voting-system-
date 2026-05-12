// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";
import {ILayer2ParameterRegistry} from "./interfaces/ILayer2ParameterRegistry.sol";
import {ILayer2AuditTrail} from "./interfaces/ILayer2AuditTrail.sol";
import {ILayer5Timelock} from "./interfaces/ILayer5Timelock.sol";
import {Layer3DataIngestionLib} from "./libraries/Layer3DataIngestionLib.sol";
import {Layer3KPILib} from "./libraries/Layer3KPILib.sol";
import {Layer3OptimizationLib} from "./libraries/Layer3OptimizationLib.sol";
import {Layer3SafetyLib} from "./libraries/Layer3SafetyLib.sol";
import {Layer3SimulationLib} from "./libraries/Layer3SimulationLib.sol";
import {Layer3TreasuryFirewall} from "./libraries/Layer3TreasuryFirewall.sol";
import {Layer3Constants} from "./libraries/Layer3Constants.sol";
import {Layer3ModelRegistry} from "./Layer3ModelRegistry.sol";

/// @notice Master Layer 3 controller — wires GATE 1→6 sequentially; GATE 7/8 live in dedicated contracts.
contract Layer3Orchestrator is Ownable {
    ILayer2ParameterRegistry public immutable registry;
    Layer3ModelRegistry public immutable models;
    ILayer2AuditTrail public auditTrail;

    /// @notice When non-zero, parameter broadcasts use Layer 5 `queueAdjustment` only (no direct L2 propose).
    address public timelock;

    uint256 public immutable minTimelockBlocks;

    mapping(address => bool) public oracleWhitelist;
    mapping(bytes32 => bool) public usedSafeSetHashes;

    uint256 public cumulativeQuorumReductionWad;
    uint256 public dynamicQuorumMultiplierWad = Layer3Constants.DQM_DEFAULT_WAD;

    bytes32 public lastCycleId;

    event OracleWhitelisted(address indexed oracle, bool allowed);
    event EvolutionCycle(
        bytes32 indexed cycleId,
        bytes32 frameHash,
        bool anomalyFlag,
        bytes32 kpiHash,
        bytes32 simHash,
        bool conservativeFallback
    );
    event Gate6Broadcast(bytes32 indexed cycleId, bytes32 safeSetHash, bytes32 justificationHash);
    event SafetyViolation(bytes32 indexed cycleId, uint8 violationCode);
    event ConservativeFallback(bytes32 indexed cycleId, string reason);

    error Gate3InactiveModel();
    error Gate6JustificationTooShort();
    error Gate6DuplicateSafeSet();
    error SafetyRejected(uint8 violation);

    event TimelockPolicy(bytes32 indexed cycleId, uint256 minBlocksExpected);
    event TimelockWired(address indexed timelock);
    event FailsafeAdjustmentQueued(bytes32 indexed cycleId, bytes32 indexed adjustmentId);

    constructor(
        address initialOwner,
        address registry_,
        address modelRegistry_,
        uint256 minTimelockBlocks_
    ) Ownable(initialOwner) {
        registry = ILayer2ParameterRegistry(registry_);
        models = Layer3ModelRegistry(modelRegistry_);
        minTimelockBlocks = minTimelockBlocks_;
    }

    function setOracle(address oracle, bool allowed) external onlyOwner {
        oracleWhitelist[oracle] = allowed;
        emit OracleWhitelisted(oracle, allowed);
    }

    function setAuditTrail(address trail) external onlyOwner {
        auditTrail = ILayer2AuditTrail(trail);
    }

    function setTimelock(address timelock_) external onlyOwner {
        timelock = timelock_;
        emit TimelockWired(timelock_);
    }

    /// @notice Decay cumulative quorum reduction (ops hygiene between epochs).
    function decayCumulativeReduction(uint256 numerator, uint256 denominator) external onlyOwner {
        cumulativeQuorumReductionWad = (cumulativeQuorumReductionWad * numerator) / denominator;
    }

    /// @notice Executes GATE 1 → 2 → 3 → (4 sim) → 4 safety → 5/6 broadcast to Layer 2 registry.
    function executeEvolutionCycle(
        bytes32 dataPayloadHash,
        uint256 onChainReferenceTime,
        uint256 offChainReferenceTime,
        Layer3DataIngestionLib.Attestation[3] calldata attestations,
        Layer3KPILib.RawMetrics calldata raw,
        uint256 timeWindowSecs,
        bytes calldata justification,
        bytes32 modelVersionId
    ) external onlyOwner returns (bytes32 cycleId) {
        if (!models.isActive(modelVersionId)) revert Gate3InactiveModel();
        if (justification.length < 100) revert Gate6JustificationTooShort();

        (bytes32 frameHash, bool anomalyFlag) = Layer3DataIngestionLib.validateFrame(
            oracleWhitelist,
            dataPayloadHash,
            onChainReferenceTime,
            offChainReferenceTime,
            attestations
        );

        Layer3KPILib.KPIMetrics memory kpi = Layer3KPILib.compute(raw, timeWindowSecs);
        bytes32 kpiHash = keccak256(abi.encode(kpi));

        Layer3OptimizationLib.ParameterSetWad memory current = _loadCurrentParams();
        Layer3OptimizationLib.OptimizationResult memory opt =
            Layer3OptimizationLib.optimize(kpi, current);

        bytes32 simHash = Layer3SimulationLib.requirePass(kpi, current, opt, modelVersionId);

        Layer3SafetyLib.CumulativeState memory cum =
            Layer3SafetyLib.CumulativeState({quorumReductionSumWad: cumulativeQuorumReductionWad});
        (bool safe, Layer3SafetyLib.Violation viol) =
            Layer3SafetyLib.enforce(current, opt.proposed, cum);
        if (!safe) {
            emit SafetyViolation(bytes32(0), uint8(viol));
            _audit(
                keccak256("GATE_4_SAFETY"),
                keccak256("SAFETY_REJECT"),
                bytes32(uint256(viol)),
                false,
                ILayer2AuditTrail.Severity.HIGH,
                keccak256(abi.encode(opt.proposed))
            );
            revert SafetyRejected(uint8(viol));
        }

        bytes32 safeSetHash = keccak256(abi.encode(opt.proposed, frameHash, simHash, kpiHash));
        if (usedSafeSetHashes[safeSetHash]) revert Gate6DuplicateSafeSet();

        cycleId =
            keccak256(abi.encodePacked(block.chainid, address(this), safeSetHash, block.number));
        lastCycleId = cycleId;

        emit EvolutionCycle(
            cycleId, frameHash, anomalyFlag, kpiHash, simHash, opt.conservativeFallback
        );

        if (opt.conservativeFallback) {
            emit ConservativeFallback(cycleId, "confidence_or_no_change");
            _audit(
                keccak256("GATE_3_OPTIM"),
                keccak256("CONSERVATIVE_FALLBACK"),
                cycleId,
                true,
                ILayer2AuditTrail.Severity.INFO,
                safeSetHash
            );
            usedSafeSetHashes[safeSetHash] = true;
            return cycleId;
        }

        bytes32 justificationHash = keccak256(abi.encodePacked(justification, safeSetHash));
        emit Gate6Broadcast(cycleId, safeSetHash, justificationHash);
        emit TimelockPolicy(cycleId, minTimelockBlocks);

        if (timelock != address(0)) {
            _broadcastViaFailsafe(cycleId, opt.proposed);
        } else {
            _broadcastViaLegacy(justificationHash, opt.proposed);
        }

        dynamicQuorumMultiplierWad = opt.proposed.dynamicQuorumMultiplierWad;

        if (opt.proposed.quorumThresholdWad < current.quorumThresholdWad) {
            cumulativeQuorumReductionWad +=
                current.quorumThresholdWad - opt.proposed.quorumThresholdWad;
        }

        usedSafeSetHashes[safeSetHash] = true;

        _audit(
            keccak256("GATE_6_TIMELOCK"),
            keccak256("BROADCAST_PROPOSALS"),
            cycleId,
            true,
            ILayer2AuditTrail.Severity.INFO,
            safeSetHash
        );

        return cycleId;
    }

    function _broadcastViaFailsafe(bytes32 cycleId, Layer3OptimizationLib.ParameterSetWad memory proposed)
        internal
    {
        Layer3TreasuryFirewall.verifyParameterBroadcast(
            address(registry), timelock, timelock, 0, ILayer5Timelock.queueAdjustment.selector
        );
        ILayer5Timelock.ParameterSet memory packed = _buildQueuedParameterSet(proposed);
        if (_queuedSetDiffersFromRegistry(packed)) {
            bytes32 adjId = ILayer5Timelock(timelock).queueAdjustment(packed);
            emit FailsafeAdjustmentQueued(cycleId, adjId);
        }
    }

    function _broadcastViaLegacy(bytes32 justificationHash, Layer3OptimizationLib.ParameterSetWad memory proposed)
        internal
    {
        Layer3TreasuryFirewall.verifyParameterBroadcast(
            address(registry),
            address(0),
            address(registry),
            0,
            ILayer2ParameterRegistry.proposeParameterAdjustment.selector
        );
        _maybeProposeQuorum(
            ILayer2ParameterRegistry.ParamKey.QUORUM_THRESHOLD,
            proposed.quorumThresholdWad,
            justificationHash
        );
        _maybeProposeUint(
            ILayer2ParameterRegistry.ParamKey.VOTING_DURATION,
            proposed.votingDurationBlocks,
            justificationHash
        );
        _maybeProposeUint(
            ILayer2ParameterRegistry.ParamKey.CREDIT_REGEN_RATE,
            proposed.voiceCreditRegenerationRate,
            justificationHash
        );
        _maybeProposeUint(
            ILayer2ParameterRegistry.ParamKey.PROPOSAL_THRESHOLD,
            proposed.proposalDepositAmount,
            justificationHash
        );
    }

    function _buildQueuedParameterSet(Layer3OptimizationLib.ParameterSetWad memory proposed)
        internal
        view
        returns (ILayer5Timelock.ParameterSet memory p)
    {
        p.votingDuration = _nextUintRegistryValue(
            ILayer2ParameterRegistry.ParamKey.VOTING_DURATION, proposed.votingDurationBlocks
        );
        p.quorumThreshold = _nextQuorumRegistryValue(proposed.quorumThresholdWad);
        p.creditRegenRate = _nextUintRegistryValue(
            ILayer2ParameterRegistry.ParamKey.CREDIT_REGEN_RATE, proposed.voiceCreditRegenerationRate
        );
        p.maxCreditCap = registry.values(ILayer2ParameterRegistry.ParamKey.MAX_CREDIT_CAP);
        p.submissionDelay = registry.values(ILayer2ParameterRegistry.ParamKey.SUBMISSION_DELAY);
        p.proposalThreshold = _nextUintRegistryValue(
            ILayer2ParameterRegistry.ParamKey.PROPOSAL_THRESHOLD, proposed.proposalDepositAmount
        );
    }

    function _queuedSetDiffersFromRegistry(ILayer5Timelock.ParameterSet memory p)
        internal
        view
        returns (bool)
    {
        return registry.values(ILayer2ParameterRegistry.ParamKey.VOTING_DURATION) != p.votingDuration
            || registry.values(ILayer2ParameterRegistry.ParamKey.QUORUM_THRESHOLD) != p.quorumThreshold
            || registry.values(ILayer2ParameterRegistry.ParamKey.CREDIT_REGEN_RATE) != p.creditRegenRate
            || registry.values(ILayer2ParameterRegistry.ParamKey.MAX_CREDIT_CAP) != p.maxCreditCap
            || registry.values(ILayer2ParameterRegistry.ParamKey.SUBMISSION_DELAY) != p.submissionDelay
            || registry.values(ILayer2ParameterRegistry.ParamKey.PROPOSAL_THRESHOLD) != p.proposalThreshold;
    }

    function _nextQuorumRegistryValue(uint256 proposedWad) internal view returns (uint256) {
        ILayer2ParameterRegistry.ParamKey key = ILayer2ParameterRegistry.ParamKey.QUORUM_THRESHOLD;
        (uint256 rmin, uint256 rmax) = registry.bounds(key);
        uint256 curOn = registry.values(key);
        uint256 curWad = _toWad(curOn, rmin, rmax);
        int256 dWad = int256(proposedWad) - int256(curWad);
        if (dWad == 0) return curOn;
        int256 rspan = int256(rmax - rmin);
        int256 wspan = int256(Layer3Constants.QUORUM_MAX_WAD - Layer3Constants.QUORUM_MIN_WAD);
        int256 dReg = dWad * rspan / wspan;
        if (dReg == 0) {
            dReg = dWad > 0 ? int256(1) : int256(-1);
        }
        int256 nextSigned = int256(curOn) + dReg;
        if (nextSigned < int256(rmin)) nextSigned = int256(rmin);
        if (nextSigned > int256(rmax)) nextSigned = int256(rmax);
        return uint256(nextSigned);
    }

    function _nextUintRegistryValue(ILayer2ParameterRegistry.ParamKey key, uint256 proposedOn)
        internal
        view
        returns (uint256)
    {
        (uint256 rmin, uint256 rmax) = registry.bounds(key);
        uint256 cur = registry.values(key);
        if (proposedOn == cur) return cur;
        return _clampRegistry(proposedOn, rmin, rmax);
    }

    function _maybeProposeQuorum(
        ILayer2ParameterRegistry.ParamKey key,
        uint256 proposedWad,
        bytes32 justificationHash
    ) internal {
        (uint256 rmin, uint256 rmax) = registry.bounds(key);
        uint256 curOn = registry.values(key);
        uint256 curWad = _toWad(curOn, rmin, rmax);
        int256 dWad = int256(proposedWad) - int256(curWad);
        if (dWad == 0) return;
        int256 rspan = int256(rmax - rmin);
        int256 wspan = int256(Layer3Constants.QUORUM_MAX_WAD - Layer3Constants.QUORUM_MIN_WAD);
        int256 dReg = dWad * rspan / wspan;
        if (dReg == 0) {
            dReg = dWad > 0 ? int256(1) : int256(-1);
        }
        int256 nextSigned = int256(curOn) + dReg;
        if (nextSigned < int256(rmin)) nextSigned = int256(rmin);
        if (nextSigned > int256(rmax)) nextSigned = int256(rmax);
        uint256 proposedOn = uint256(nextSigned);
        if (proposedOn == curOn) return;
        registry.proposeParameterAdjustment(key, proposedOn, bytes(""), justificationHash);
    }

    function _maybeProposeUint(
        ILayer2ParameterRegistry.ParamKey key,
        uint256 proposedOn,
        bytes32 justificationHash
    ) internal {
        (uint256 rmin, uint256 rmax) = registry.bounds(key);
        uint256 cur = registry.values(key);
        if (proposedOn == cur) return;
        uint256 clamped = _clampRegistry(proposedOn, rmin, rmax);
        if (clamped == cur) return;
        registry.proposeParameterAdjustment(key, clamped, bytes(""), justificationHash);
    }

    function _loadCurrentParams()
        internal
        view
        returns (Layer3OptimizationLib.ParameterSetWad memory c)
    {
        (uint256 qmin, uint256 qmax) =
            registry.bounds(ILayer2ParameterRegistry.ParamKey.QUORUM_THRESHOLD);
        uint256 qv = registry.values(ILayer2ParameterRegistry.ParamKey.QUORUM_THRESHOLD);
        c.quorumThresholdWad = _toWad(qv, qmin, qmax);

        c.votingDurationBlocks = registry.values(ILayer2ParameterRegistry.ParamKey.VOTING_DURATION);
        c.voiceCreditRegenerationRate =
            registry.values(ILayer2ParameterRegistry.ParamKey.CREDIT_REGEN_RATE);
        c.proposalDepositAmount =
            registry.values(ILayer2ParameterRegistry.ParamKey.PROPOSAL_THRESHOLD);
        c.dynamicQuorumMultiplierWad = dynamicQuorumMultiplierWad;
    }

    function _toWad(uint256 v, uint256 rmin, uint256 rmax) internal pure returns (uint256) {
        if (rmax <= rmin) return Layer3Constants.QUORUM_DEFAULT_WAD;
        return Layer3Constants.QUORUM_MIN_WAD
            + (v - rmin) * (Layer3Constants.QUORUM_MAX_WAD - Layer3Constants.QUORUM_MIN_WAD)
                / (rmax - rmin);
    }

    function _clampRegistry(uint256 v, uint256 rmin, uint256 rmax)
        internal
        pure
        returns (uint256)
    {
        if (v < rmin) return rmin;
        if (v > rmax) return rmax;
        return v;
    }

    function _audit(
        bytes32 gateId,
        bytes32 actionId,
        bytes32 subjectId,
        bool success,
        ILayer2AuditTrail.Severity severity,
        bytes32 contextHash
    ) internal {
        if (address(auditTrail) == address(0)) return;
        auditTrail.recordGateEvent(gateId, actionId, subjectId, success, severity, contextHash);
    }
}
