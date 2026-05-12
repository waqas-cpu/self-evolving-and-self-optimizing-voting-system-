// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ParameterSet} from "../Layer5Types.sol";

interface IBaselineRegistry {
    event BaselineRestored(address indexed restorer, uint256 timestamp, bytes32 paramsHash);
    event CurrentConfigUpdated(bytes32 newConfigHash);

    function restoreToBaseline() external;

    function recordExecutedConfig(bytes32 newConfigHash) external;

    function getBaselineHash() external view returns (bytes32);

    function getCurrentHash() external view returns (bytes32);

    function baselineParams() external view returns (ParameterSet memory);
}
