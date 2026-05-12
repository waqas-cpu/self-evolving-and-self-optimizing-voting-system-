// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILayer5Timelock} from "../contracts/interfaces/ILayer5Timelock.sol";

contract MockLayer5Timelock is ILayer5Timelock {
    uint256 public queueCount;
    ParameterSet public lastQueued;

    function queueAdjustment(ParameterSet calldata params) external returns (bytes32 id) {
        queueCount += 1;
        lastQueued = params;
        id = keccak256(abi.encode(params, queueCount, block.timestamp));
    }
}
