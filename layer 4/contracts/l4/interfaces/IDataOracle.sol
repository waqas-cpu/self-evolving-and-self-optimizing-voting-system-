// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Gate L4-05 — sole Layer 3 consumption surface for aggregated oracle metrics.
interface IDataOracle {
    struct AggregatedMetric {
        bytes32 metricId;
        uint256 value;
        uint256 confidenceScore;
        uint256 freshnessScore;
        uint256 blockHeight;
        bytes32 aggregationProof;
        uint256 sourceCount;
    }

    function getMetric(bytes32 metricId) external view returns (AggregatedMetric memory);

    function getMetricBatch(bytes32[] calldata metricIds)
        external
        view
        returns (AggregatedMetric[] memory);
}
