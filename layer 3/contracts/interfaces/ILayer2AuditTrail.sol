// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ILayer2AuditTrail {
    enum Severity {
        INFO,
        WARN,
        HIGH,
        CRITICAL
    }

    function recordGateEvent(
        bytes32 gateId,
        bytes32 actionId,
        bytes32 subjectId,
        bool success,
        Severity severity,
        bytes32 contextHash
    ) external;
}
