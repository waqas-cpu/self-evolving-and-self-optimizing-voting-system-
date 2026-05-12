// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDataOracle} from "./interfaces/IDataOracle.sol";

/// @notice Canonical leaf preimage for Merkle batches (must match `services/l4` Merkle builder).
library Layer4MetricEncoding {
    function leafHash(IDataOracle.AggregatedMetric memory m) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                m.metricId,
                m.value,
                m.confidenceScore,
                m.freshnessScore,
                m.blockHeight,
                m.sourceCount
            )
        );
    }

    function leafHashCalldata(IDataOracle.AggregatedMetric calldata m) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                m.metricId,
                m.value,
                m.confidenceScore,
                m.freshnessScore,
                m.blockHeight,
                m.sourceCount
            )
        );
    }
}
