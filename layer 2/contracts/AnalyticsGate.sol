// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";
import {ILayer2AuditTrail} from "./interfaces/ILayer2AuditTrail.sol";

contract AnalyticsGate is Ownable {
    enum DataType {
        VOTER_TURNOUT,
        TREASURY_VELOCITY,
        TOKEN_PRICE,
        PROPOSAL_SUCCESS_RATE,
        CREDIT_UTILIZATION
    }

    struct Snapshot {
        DataType dataType;
        uint256 value;
        uint256 roundId;
        uint256 storedAtBlock;
    }

    uint256 public constant MIN_ORACLE_THRESHOLD = 2;
    mapping(DataType => uint256) public lastProcessedRoundId;
    mapping(address => bool) public oracleSigners;
    Snapshot[] public snapshots;
    ILayer2AuditTrail public auditTrail;

    event OracleDataIngested(DataType indexed dataType, uint256 value, uint256 roundId, uint256 timestamp);
    error ThresholdNotMet();
    error StaleRound();
    error UnauthorizedSigner();

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setAuditTrail(ILayer2AuditTrail trail) external onlyOwner {
        auditTrail = trail;
    }

    function setOracleSigner(address signer, bool ok) external onlyOwner {
        oracleSigners[signer] = ok;
    }

    function ingestOracleData(DataType dataType, uint256 value, address[] calldata signers, uint256 roundId)
        external
        returns (bool verified, uint256 storedAtBlock)
    {
        if (signers.length < MIN_ORACLE_THRESHOLD) revert ThresholdNotMet();
        if (roundId <= lastProcessedRoundId[dataType]) revert StaleRound();
        for (uint256 i; i < signers.length; ++i) {
            if (!oracleSigners[signers[i]]) revert UnauthorizedSigner();
        }
        lastProcessedRoundId[dataType] = roundId;
        storedAtBlock = block.number;
        snapshots.push(Snapshot(dataType, value, roundId, storedAtBlock));
        emit OracleDataIngested(dataType, value, roundId, block.timestamp);
        _audit(
            keccak256("GATE_5_DATA_FEED"),
            keccak256("INGEST_ORACLE_DATA"),
            keccak256(abi.encodePacked(uint256(dataType), roundId)),
            true,
            ILayer2AuditTrail.Severity.INFO,
            keccak256(abi.encodePacked(value, signers.length))
        );
        return (true, storedAtBlock);
    }

    function getAnalyticsSnapshot(uint256 fromBlock, uint256 toBlock) external view returns (Snapshot[] memory out) {
        uint256 count;
        for (uint256 i; i < snapshots.length; ++i) {
            if (snapshots[i].storedAtBlock >= fromBlock && snapshots[i].storedAtBlock <= toBlock) count++;
        }
        out = new Snapshot[](count);
        uint256 idx;
        for (uint256 i; i < snapshots.length; ++i) {
            if (snapshots[i].storedAtBlock >= fromBlock && snapshots[i].storedAtBlock <= toBlock) {
                out[idx++] = snapshots[i];
            }
        }
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
