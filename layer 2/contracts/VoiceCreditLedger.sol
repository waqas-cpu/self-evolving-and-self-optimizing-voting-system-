// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";
import {ParameterRegistry} from "./ParameterRegistry.sol";
import {ILayer2AuditTrail} from "./interfaces/ILayer2AuditTrail.sol";

contract VoiceCreditLedger is Ownable {
    struct LockedCredit {
        uint256 amount;
        bool exists;
    }

    ParameterRegistry public immutable params;
    mapping(address => uint256) public availableCredits;
    mapping(address => uint256) public lockedCredits;
    mapping(address => uint256) public lastRegenerationBlock;
    mapping(address => mapping(bytes32 => LockedCredit)) public lockedByProposal;
    uint256 public globalCreditPool;
    mapping(address => bool) public trustedCaller;
    ILayer2AuditTrail public auditTrail;

    event CreditsAllocated(address indexed identity, uint256 amount);
    event CreditsLocked(address indexed identity, bytes32 indexed proposalId, uint256 amount, uint256 timestamp);
    event CreditsReleased(address indexed identity, bytes32 indexed proposalId, uint256 amount, uint256 timestamp);
    event CreditsSlashed(address indexed identity, uint256 amount, bytes32 indexed reasonHash);

    error UnauthorizedCaller();
    error InsufficientCredits();
    error CapExceeded();
    error NoLockedCredits();

    constructor(address initialOwner, ParameterRegistry _params) Ownable(initialOwner) {
        params = _params;
    }

    function setAuditTrail(ILayer2AuditTrail trail) external onlyOwner {
        auditTrail = trail;
    }

    modifier onlyTrusted() {
        if (!trustedCaller[msg.sender]) revert UnauthorizedCaller();
        _;
    }

    function setTrustedCaller(address caller, bool ok) external onlyOwner {
        trustedCaller[caller] = ok;
    }

    function allocateCredits(address identity, uint256 amount) external onlyTrusted {
        _regenerate(identity);
        uint256 cap = params.values(ParameterRegistry.ParamKey.MAX_CREDIT_CAP);
        uint256 newAvailable = availableCredits[identity] + amount;
        if (newAvailable + lockedCredits[identity] > cap) revert CapExceeded();
        availableCredits[identity] = newAvailable;
        globalCreditPool += amount;
        emit CreditsAllocated(identity, amount);
        _audit(
            keccak256("GATE_2_VOICE_CREDIT"),
            keccak256("ALLOCATE_CREDITS"),
            keccak256(abi.encodePacked(identity)),
            true,
            ILayer2AuditTrail.Severity.INFO,
            keccak256(abi.encodePacked(amount, newAvailable))
        );
    }

    function regenerateCredits(address identity) external {
        _regenerate(identity);
    }

    function _regenerate(address identity) internal {
        uint256 last = lastRegenerationBlock[identity];
        if (last == 0) {
            lastRegenerationBlock[identity] = block.number;
            return;
        }
        uint256 rate = params.values(ParameterRegistry.ParamKey.CREDIT_REGEN_RATE);
        uint256 cap = params.values(ParameterRegistry.ParamKey.MAX_CREDIT_CAP);
        uint256 delta = block.number - last;
        if (delta == 0) return;
        uint256 regen = delta * rate;
        uint256 cur = availableCredits[identity];
        uint256 maxGain = cap > cur + lockedCredits[identity] ? cap - (cur + lockedCredits[identity]) : 0;
        if (regen > maxGain) regen = maxGain;
        availableCredits[identity] = cur + regen;
        globalCreditPool += regen;
        lastRegenerationBlock[identity] = block.number;
    }

    function lockCredits(address identity, bytes32 proposalId, uint256 amount) external onlyTrusted {
        _regenerate(identity);
        if (amount > availableCredits[identity]) revert InsufficientCredits();
        availableCredits[identity] -= amount;
        lockedCredits[identity] += amount;
        lockedByProposal[identity][proposalId].amount += amount;
        lockedByProposal[identity][proposalId].exists = true;
        emit CreditsLocked(identity, proposalId, amount, block.timestamp);
        _audit(
            keccak256("GATE_2_VOICE_CREDIT"),
            keccak256("LOCK_CREDITS"),
            proposalId,
            true,
            ILayer2AuditTrail.Severity.INFO,
            keccak256(abi.encodePacked(identity, amount))
        );
    }

    function releaseCredits(address identity, bytes32 proposalId) external onlyTrusted returns (uint256 releasedAmount) {
        LockedCredit storage l = lockedByProposal[identity][proposalId];
        if (!l.exists || l.amount == 0) revert NoLockedCredits();
        releasedAmount = l.amount;
        l.amount = 0;
        availableCredits[identity] += releasedAmount;
        lockedCredits[identity] -= releasedAmount;
        emit CreditsReleased(identity, proposalId, releasedAmount, block.timestamp);
        _audit(
            keccak256("GATE_2_VOICE_CREDIT"),
            keccak256("RELEASE_CREDITS"),
            proposalId,
            true,
            ILayer2AuditTrail.Severity.INFO,
            keccak256(abi.encodePacked(identity, releasedAmount))
        );
    }

    function slashCredits(address identity, uint256 amount, bytes32 reasonHash) external onlyTrusted {
        uint256 fromAvailable = amount > availableCredits[identity] ? availableCredits[identity] : amount;
        availableCredits[identity] -= fromAvailable;
        uint256 remaining = amount - fromAvailable;
        if (remaining > 0) {
            if (remaining > lockedCredits[identity]) remaining = lockedCredits[identity];
            lockedCredits[identity] -= remaining;
        }
        globalCreditPool -= (fromAvailable + remaining);
        emit CreditsSlashed(identity, amount, reasonHash);
        _audit(
            keccak256("GATE_2_VOICE_CREDIT"),
            keccak256("SLASH_CREDITS"),
            keccak256(abi.encodePacked(identity)),
            true,
            ILayer2AuditTrail.Severity.HIGH,
            reasonHash
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
