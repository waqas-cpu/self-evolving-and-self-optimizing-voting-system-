// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";
import {ILayer2AuditTrail} from "./interfaces/ILayer2AuditTrail.sol";

contract ExecutionRouter is Ownable {
    struct QueueItem {
        bytes payload;
        address target;
        bool queued;
        bool executed;
        bool failed;
        uint256 nonce;
    }

    mapping(bytes32 => QueueItem) public queue;
    uint256 public executionNonce;
    address public proposalLifecycle;
    mapping(address => bool) public restrictedTargets;
    ILayer2AuditTrail public auditTrail;

    event ExecutionQueued(bytes32 indexed proposalId, uint256 nonce);
    event ExecutionRouted(bytes32 indexed proposalId, bool success, bytes returnData);

    error OnlyProposalLifecycle();
    error AlreadyExecuted();
    error NotQueued();
    error RestrictedTarget();

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setAuditTrail(ILayer2AuditTrail trail) external onlyOwner {
        auditTrail = trail;
    }

    function setProposalLifecycle(address lifecycle) external onlyOwner {
        proposalLifecycle = lifecycle;
    }

    function setRestrictedTarget(address target, bool restricted) external onlyOwner {
        restrictedTargets[target] = restricted;
    }

    function queueExecution(bytes32 proposalId, address target, bytes calldata payload) external {
        if (msg.sender != proposalLifecycle) revert OnlyProposalLifecycle();
        if (restrictedTargets[target]) revert RestrictedTarget();
        QueueItem storage item = queue[proposalId];
        item.target = target;
        item.payload = payload;
        item.queued = true;
        item.nonce = ++executionNonce;
        emit ExecutionQueued(proposalId, item.nonce);
        _audit(
            keccak256("GATE_3_PROPOSAL"),
            keccak256("QUEUE_EXECUTION"),
            proposalId,
            true,
            ILayer2AuditTrail.Severity.INFO,
            keccak256(abi.encodePacked(target, item.nonce))
        );
    }

    function execute(bytes32 proposalId) external returns (bool success, bytes memory returnData) {
        QueueItem storage item = queue[proposalId];
        if (!item.queued) revert NotQueued();
        if (item.executed) revert AlreadyExecuted();
        (success, returnData) = item.target.call(item.payload);
        item.executed = success;
        item.failed = !success;
        emit ExecutionRouted(proposalId, success, returnData);
        _audit(
            keccak256("GATE_3_PROPOSAL"),
            keccak256("ROUTE_EXECUTION"),
            proposalId,
            success,
            success ? ILayer2AuditTrail.Severity.INFO : ILayer2AuditTrail.Severity.HIGH,
            keccak256(returnData)
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
