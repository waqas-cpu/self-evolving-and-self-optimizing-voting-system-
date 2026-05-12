// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Commit–reveal anchor for aggregated batches (Module 4F).
interface IDataBuffer {
    function getMerkleRoot(bytes32 batchId) external view returns (bytes32);

    function isRevealed(bytes32 batchId) external view returns (bool);

    function isConsumed(bytes32 batchId) external view returns (bool);

    function consume(bytes32 batchId) external;
}
