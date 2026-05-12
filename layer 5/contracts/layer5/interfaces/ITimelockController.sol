// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ParameterSet} from "../Layer5Types.sol";

interface ITimelockController {
    event AdjustmentQueued(bytes32 indexed id, ParameterSet params, uint256 executableAt);
    event AdjustmentExecuted(bytes32 indexed id);
    event AdjustmentVetoed(bytes32 indexed id, address vetoer, string justification);

    function queueAdjustment(ParameterSet calldata params) external returns (bytes32 id);

    function executeAdjustment(bytes32 id) external;

    function cancelAdjustment(bytes32 id, address vetoActor, string calldata justification) external;

    /// @return state Raw `Layer5State` enum ordinal (0 = DORMANT … 3 = VETOED).
    function adjustmentState(bytes32 id) external view returns (uint8 state);
}
