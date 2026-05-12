// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";
import {ILayer2AuditTrail} from "./interfaces/ILayer2AuditTrail.sol";

contract Layer2AuditTrail is Ownable, ILayer2AuditTrail {
    struct AuditRecord {
        bytes32 gateId;
        bytes32 actionId;
        bytes32 subjectId;
        bool success;
        Severity severity;
        bytes32 contextHash;
        uint256 blockNumber;
        uint256 timestamp;
        address reporter;
    }

    mapping(address => bool) public reporters;
    AuditRecord[] internal records;

    event GateAuditRecorded(
        bytes32 indexed gateId,
        bytes32 indexed actionId,
        bytes32 indexed subjectId,
        bool success,
        Severity severity,
        bytes32 contextHash,
        address reporter
    );

    error UnauthorizedReporter();

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setReporter(address reporter, bool allowed) external onlyOwner {
        reporters[reporter] = allowed;
    }

    function recordGateEvent(
        bytes32 gateId,
        bytes32 actionId,
        bytes32 subjectId,
        bool success,
        Severity severity,
        bytes32 contextHash
    ) external {
        if (!reporters[msg.sender]) revert UnauthorizedReporter();
        records.push(
            AuditRecord(gateId, actionId, subjectId, success, severity, contextHash, block.number, block.timestamp, msg.sender)
        );
        emit GateAuditRecorded(gateId, actionId, subjectId, success, severity, contextHash, msg.sender);
    }

    function recordCount() external view returns (uint256) {
        return records.length;
    }

    function getRecord(uint256 index) external view returns (AuditRecord memory) {
        return records[index];
    }
}
