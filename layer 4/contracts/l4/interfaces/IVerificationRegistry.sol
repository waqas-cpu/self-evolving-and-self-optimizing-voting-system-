// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice L4-01 / L4-03 / L4-07 — oracle identity, stake, and fault accounting.
interface IVerificationRegistry {
    function isApproved(address oracle) external view returns (bool);

    function stakeOf(address oracle) external view returns (uint256);

    function faultCount(address oracle) external view returns (uint256);

    function activeOracleCount() external view returns (uint256);

    function activeOracleAt(uint256 index) external view returns (address);
}
