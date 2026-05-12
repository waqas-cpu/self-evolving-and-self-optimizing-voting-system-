// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ParameterSet} from "../Layer5Types.sol";

/// @notice Minimal Layer 2 surface for Layer 5 timelock apply + baseline restore.
interface ILayer2ParameterRegistryL5 {
    function applyLayer5ParameterSet(ParameterSet calldata p) external;

    function restoreBaselineFromLayer5() external;
}
