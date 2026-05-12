// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ParameterSet} from "../../contracts/layer5/Layer5Types.sol";
import {ILayer2ParameterRegistryL5} from "../../contracts/layer5/interfaces/ILayer2ParameterRegistryL5.sol";

/// @notice Stand-in for Layer 2 `ParameterRegistry` in Layer 5 unit tests (no cross-folder Foundry imports).
contract MockLayer2Registry is ILayer2ParameterRegistryL5 {
    ParameterSet public applied;
    bool public safeMode;

    constructor(ParameterSet memory initial) {
        applied = initial;
        safeMode = true;
    }

    function applyLayer5ParameterSet(ParameterSet calldata p) external {
        applied = p;
        safeMode = false;
    }

    function restoreBaselineFromLayer5() external {
        applied = ParameterSet({
            votingDuration: 1_000,
            quorumThreshold: 1_000,
            creditRegenRate: 10,
            maxCreditCap: 10_000,
            submissionDelay: 50,
            proposalThreshold: 100
        });
        safeMode = true;
    }
}
