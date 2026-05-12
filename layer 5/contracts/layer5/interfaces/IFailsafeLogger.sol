// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ParameterSet} from "../Layer5Types.sol";

interface IFailsafeLogger {
    event ModuleAuthorized(address indexed module);
    event StateDiffLogged(
        bytes32 indexed subjectId, bytes32 indexed beforeHash, bytes32 indexed afterHash, address caller
    );
    event VetoJustificationStored(bytes32 indexed adjustmentId, bytes32 justificationHash);
    event LogAppended(uint256 indexed logId, uint8 eventType, bytes32 entryHash);

    function authorizeModule(address module) external;

    function logStateDiff(bytes32 subjectId, bytes32 beforeHash, bytes32 afterHash) external;

    function storeVetoJustification(bytes32 adjustmentId, string calldata justification) external;

    function appendChainLog(uint8 eventType, bytes calldata payload) external returns (uint256 logId);
}
