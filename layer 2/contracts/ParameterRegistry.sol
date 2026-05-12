// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";
import {ILayer2AuditTrail} from "./interfaces/ILayer2AuditTrail.sol";

contract ParameterRegistry is Ownable {
    enum ParamKey {
        VOTING_DURATION,
        QUORUM_THRESHOLD,
        CREDIT_REGEN_RATE,
        MAX_CREDIT_CAP,
        SUBMISSION_DELAY,
        PROPOSAL_THRESHOLD
    }

    struct Bounds {
        uint256 min;
        uint256 max;
    }
    struct PendingAdjustment {
        ParamKey key;
        uint256 newValue;
        uint256 effectiveBlock;
        bool vetoed;
        bool applied;
    }

    uint256 public constant TIMELOCK_DURATION_BLOCKS = 50;
    uint256 public constant COOLDOWN_BLOCKS = 20;

    mapping(ParamKey => Bounds) public bounds;
    mapping(ParamKey => uint256) public values;
    mapping(ParamKey => uint256) public lastAdjustedBlock;
    mapping(bytes32 => PendingAdjustment) public pending;
    mapping(address => bool) public aiOracleWhitelist;
    mapping(address => bool) public vetoSigners;
    bool public safeMode;
    ILayer2AuditTrail public auditTrail;

    /// @notice Layer 5 TimelockController — sole caller for batched parameter application.
    address public layer5Timelock;
    /// @notice Layer 5 BaselineRegistry — sole caller for atomic baseline restoration.
    address public layer5BaselineRegistry;

    /// @notice When true, `proposeParameterAdjustment` reverts — all changes must go through Layer 5 timelock.
    bool public directOracleProposalsFrozen;

    event ParameterAdjustmentProposed(bytes32 indexed adjustmentId, ParamKey indexed key, uint256 newValue, uint256 effectiveBlock);
    event ParameterAdjustmentApplied(bytes32 indexed adjustmentId, uint256 oldValue, uint256 newValue);
    event ParameterAdjustmentVetoed(bytes32 indexed adjustmentId, address indexed vetoer);
    event EmergencyReverted();

    error OutOfBounds();
    error NotWhitelistedOracle();
    error CooldownActive();
    error TimelockNotExpired();
    error AdjustmentNotPending();
    error UnauthorizedVeto();
    error UnauthorizedLayer5();
    error DirectOracleProposalsFrozen();

    /// @notice Packed parameter set applied by Layer 5 after its timelock (matches Layer5 `ParameterSet` layout).
    struct Layer5ParameterSet {
        uint256 votingDuration;
        uint256 quorumThreshold;
        uint256 creditRegenRate;
        uint256 maxCreditCap;
        uint256 submissionDelay;
        uint256 proposalThreshold;
    }

    constructor(address initialOwner) Ownable(initialOwner) {
        bounds[ParamKey.VOTING_DURATION] = Bounds(100, 10_000);
        bounds[ParamKey.QUORUM_THRESHOLD] = Bounds(100, 100_000);
        bounds[ParamKey.CREDIT_REGEN_RATE] = Bounds(1, 100);
        bounds[ParamKey.MAX_CREDIT_CAP] = Bounds(1_000, 1_000_000);
        bounds[ParamKey.SUBMISSION_DELAY] = Bounds(10, 1_000);
        bounds[ParamKey.PROPOSAL_THRESHOLD] = Bounds(0, 10_000);

        values[ParamKey.VOTING_DURATION] = 1_000;
        values[ParamKey.QUORUM_THRESHOLD] = 1_000;
        values[ParamKey.CREDIT_REGEN_RATE] = 10;
        values[ParamKey.MAX_CREDIT_CAP] = 10_000;
        values[ParamKey.SUBMISSION_DELAY] = 50;
        values[ParamKey.PROPOSAL_THRESHOLD] = 100;
    }

    function setAuditTrail(ILayer2AuditTrail trail) external onlyOwner {
        auditTrail = trail;
    }

    function setAIOracle(address oracle, bool whitelisted) external onlyOwner {
        aiOracleWhitelist[oracle] = whitelisted;
    }

    function setVetoSigner(address signer, bool ok) external onlyOwner {
        vetoSigners[signer] = ok;
    }

    /// @dev One-time wiring of Layer 5 contracts. Timelock applies adjustments; BaselineRegistry triggers restore.
    function setLayer5Failsafe(address timelock, address baselineRegistry) external onlyOwner {
        layer5Timelock = timelock;
        layer5BaselineRegistry = baselineRegistry;
    }

    function setDirectOracleProposalsFrozen(bool frozen) external onlyOwner {
        directOracleProposalsFrozen = frozen;
    }

    /// @notice Atomically overwrites all tunable parameters after Layer 5 timelock execution.
    function applyLayer5ParameterSet(Layer5ParameterSet calldata p) external {
        if (msg.sender != layer5Timelock) revert UnauthorizedLayer5();
        _validateAndStoreLayer5Set(p);
        safeMode = false;
    }

    /// @notice Atomic baseline restoration invoked only by Layer 5 BaselineRegistry (veto / failsafe).
    function restoreBaselineFromLayer5() external {
        if (msg.sender != layer5BaselineRegistry) revert UnauthorizedLayer5();
        _safeModeReset();
    }

    function _validateAndStoreLayer5Set(Layer5ParameterSet calldata p) internal {
        _requireInBounds(ParamKey.VOTING_DURATION, p.votingDuration);
        _requireInBounds(ParamKey.QUORUM_THRESHOLD, p.quorumThreshold);
        _requireInBounds(ParamKey.CREDIT_REGEN_RATE, p.creditRegenRate);
        _requireInBounds(ParamKey.MAX_CREDIT_CAP, p.maxCreditCap);
        _requireInBounds(ParamKey.SUBMISSION_DELAY, p.submissionDelay);
        _requireInBounds(ParamKey.PROPOSAL_THRESHOLD, p.proposalThreshold);

        values[ParamKey.VOTING_DURATION] = p.votingDuration;
        values[ParamKey.QUORUM_THRESHOLD] = p.quorumThreshold;
        values[ParamKey.CREDIT_REGEN_RATE] = p.creditRegenRate;
        values[ParamKey.MAX_CREDIT_CAP] = p.maxCreditCap;
        values[ParamKey.SUBMISSION_DELAY] = p.submissionDelay;
        values[ParamKey.PROPOSAL_THRESHOLD] = p.proposalThreshold;
    }

    function _requireInBounds(ParamKey key, uint256 newValue) internal view {
        Bounds memory b = bounds[key];
        if (newValue < b.min || newValue > b.max) revert OutOfBounds();
    }

    function proposeParameterAdjustment(ParamKey key, uint256 newValue, bytes calldata, bytes32 justificationHash)
        external
        returns (bytes32 adjustmentId, uint256 effectiveBlock)
    {
        if (directOracleProposalsFrozen) revert DirectOracleProposalsFrozen();
        if (!aiOracleWhitelist[msg.sender]) revert NotWhitelistedOracle();
        Bounds memory b = bounds[key];
        if (newValue < b.min || newValue > b.max) revert OutOfBounds();
        if (block.number < lastAdjustedBlock[key] + COOLDOWN_BLOCKS) revert CooldownActive();

        effectiveBlock = block.number + TIMELOCK_DURATION_BLOCKS;
        adjustmentId = keccak256(abi.encodePacked(msg.sender, key, newValue, justificationHash, block.number));
        pending[adjustmentId] = PendingAdjustment(key, newValue, effectiveBlock, false, false);
        emit ParameterAdjustmentProposed(adjustmentId, key, newValue, effectiveBlock);
        _audit(
            keccak256("GATE_4_PARAMETER"),
            keccak256("PROPOSE_PARAMETER_ADJUSTMENT"),
            adjustmentId,
            true,
            ILayer2AuditTrail.Severity.INFO,
            keccak256(abi.encodePacked(uint256(key), newValue, effectiveBlock))
        );
    }

    function applyParameterAdjustment(bytes32 adjustmentId) external returns (bool success, uint256 oldValue, uint256 newValue) {
        PendingAdjustment storage p = pending[adjustmentId];
        if (p.effectiveBlock == 0 || p.applied || p.vetoed) revert AdjustmentNotPending();
        if (block.number < p.effectiveBlock) revert TimelockNotExpired();
        oldValue = values[p.key];
        values[p.key] = p.newValue;
        newValue = p.newValue;
        p.applied = true;
        lastAdjustedBlock[p.key] = block.number;
        emit ParameterAdjustmentApplied(adjustmentId, oldValue, newValue);
        _audit(
            keccak256("GATE_4_PARAMETER"),
            keccak256("APPLY_PARAMETER_ADJUSTMENT"),
            adjustmentId,
            true,
            ILayer2AuditTrail.Severity.INFO,
            keccak256(abi.encodePacked(oldValue, newValue))
        );
        return (true, oldValue, newValue);
    }

    function vetoParameterAdjustment(bytes32 adjustmentId) external returns (bool) {
        if (!vetoSigners[msg.sender]) revert UnauthorizedVeto();
        PendingAdjustment storage p = pending[adjustmentId];
        if (p.effectiveBlock == 0 || p.applied || p.vetoed) revert AdjustmentNotPending();
        p.vetoed = true;
        emit ParameterAdjustmentVetoed(adjustmentId, msg.sender);
        _safeModeReset();
        _audit(
            keccak256("GATE_4_PARAMETER"),
            keccak256("VETO_PARAMETER_ADJUSTMENT"),
            adjustmentId,
            true,
            ILayer2AuditTrail.Severity.HIGH,
            keccak256(abi.encodePacked(msg.sender))
        );
        return true;
    }

    function triggerEmergencyRevert() external onlyOwner {
        _safeModeReset();
    }

    function _safeModeReset() internal {
        safeMode = true;
        values[ParamKey.VOTING_DURATION] = 1_000;
        values[ParamKey.QUORUM_THRESHOLD] = 1_000;
        values[ParamKey.CREDIT_REGEN_RATE] = 10;
        values[ParamKey.MAX_CREDIT_CAP] = 10_000;
        values[ParamKey.SUBMISSION_DELAY] = 50;
        values[ParamKey.PROPOSAL_THRESHOLD] = 100;
        emit EmergencyReverted();
        _audit(
            keccak256("GATE_6_EMERGENCY"),
            keccak256("SAFE_MODE_RESET"),
            keccak256("BASELINE_CONFIG"),
            true,
            ILayer2AuditTrail.Severity.CRITICAL,
            keccak256(abi.encodePacked(block.number, block.timestamp))
        );
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
