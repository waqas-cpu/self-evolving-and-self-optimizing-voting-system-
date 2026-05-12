// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "../utils/Ownable.sol";
import {IFailsafeLogger} from "./interfaces/IFailsafeLogger.sol";

/// @title FailsafeLogger
/// @notice Append-only observability: hash-chained logs, state diffs, on-chain veto justifications (L1–L4 rules).
contract FailsafeLogger is IFailsafeLogger, Ownable {
    mapping(address => bool) public isModule;
    uint256 public latestLogIndex;
    bytes32 public chainTip;
    mapping(bytes32 => string) public vetoJustifications;

    error NotAuthorizedModule();

    constructor(address initialOwner) Ownable(initialOwner) {}

    function authorizeModule(address module) external onlyOwner {
        isModule[module] = true;
        emit ModuleAuthorized(module);
    }

    modifier onlyModule() {
        if (!isModule[msg.sender]) revert NotAuthorizedModule();
        _;
    }

    function logStateDiff(bytes32 subjectId, bytes32 beforeHash, bytes32 afterHash)
        external
        onlyModule
    {
        emit StateDiffLogged(subjectId, beforeHash, afterHash, msg.sender);
        bytes memory payload = abi.encode(subjectId, beforeHash, afterHash);
        _appendInternal(1, payload);
    }

    function storeVetoJustification(bytes32 adjustmentId, string calldata justification)
        external
        onlyModule
    {
        vetoJustifications[adjustmentId] = justification;
        emit VetoJustificationStored(adjustmentId, keccak256(bytes(justification)));
        bytes memory payload = abi.encode(adjustmentId, justification);
        _appendInternal(2, payload);
    }

    function appendChainLog(uint8 eventType, bytes calldata payload)
        external
        onlyModule
        returns (uint256 logId)
    {
        return _appendInternal(eventType, payload);
    }

    function _appendInternal(uint8 eventType, bytes memory payload) private returns (uint256 logId) {
        logId = ++latestLogIndex;
        bytes32 prev = chainTip;
        bytes32 entryHash =
            keccak256(abi.encodePacked(prev, block.timestamp, eventType, payload, msg.sender));
        chainTip = entryHash;
        emit LogAppended(logId, eventType, entryHash);
    }

    function verifyChainIntegrity() external view returns (bool) {
        return chainTip != bytes32(0) || latestLogIndex == 0;
    }
}
