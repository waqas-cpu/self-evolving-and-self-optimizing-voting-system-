// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ParameterSet} from "../../contracts/layer5/Layer5Types.sol";
import {ILayer2ParameterRegistryL5} from "../../contracts/layer5/interfaces/ILayer2ParameterRegistryL5.sol";

contract MockRevertingL2 is ILayer2ParameterRegistryL5 {
    error AlwaysRevert();

    function applyLayer5ParameterSet(ParameterSet calldata) external pure {
        revert AlwaysRevert();
    }

    function restoreBaselineFromLayer5() external pure {}
}
