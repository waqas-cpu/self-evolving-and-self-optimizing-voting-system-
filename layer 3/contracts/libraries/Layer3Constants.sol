// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Canonical numeric bounds from Layer 3 integration-gates specification.
library Layer3Constants {
    uint256 internal constant WAD = 1e18;

    uint256 internal constant QUORUM_MIN_WAD = 5e16;
    uint256 internal constant QUORUM_MAX_WAD = 95e16;
    uint256 internal constant QUORUM_DEFAULT_WAD = 51e16;
    uint256 internal constant QUORUM_MAX_DELTA_WAD = 1e17;

    uint256 internal constant VOTING_DUR_MIN = 1000;
    uint256 internal constant VOTING_DUR_MAX = 50_000;
    uint256 internal constant VOTING_DUR_DEFAULT = 10_000;
    uint256 internal constant VOTING_DUR_MAX_DELTA = 5000;

    uint256 internal constant CREDIT_REGEN_MIN = 1;
    uint256 internal constant CREDIT_REGEN_MAX = 100;
    uint256 internal constant CREDIT_REGEN_DEFAULT = 10;
    uint256 internal constant CREDIT_REGEN_MAX_DELTA = 5;

    uint256 internal constant DEPOSIT_MIN = 100;
    uint256 internal constant DEPOSIT_MAX = 10_000;
    uint256 internal constant DEPOSIT_DEFAULT = 1000;
    uint256 internal constant DEPOSIT_MAX_DELTA = 500;

    uint256 internal constant DQM_MIN_WAD = 5e17;
    uint256 internal constant DQM_MAX_WAD = 2 * WAD;
    uint256 internal constant DQM_DEFAULT_WAD = WAD;
    uint256 internal constant DQM_MAX_DELTA_WAD = 2e17;

    uint256 internal constant MIN_CONFIDENCE_WAD = 7e17;
}
