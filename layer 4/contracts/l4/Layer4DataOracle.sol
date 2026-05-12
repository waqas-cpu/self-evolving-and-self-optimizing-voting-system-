// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";
import {IDataOracle} from "./interfaces/IDataOracle.sol";
import {IDataBuffer} from "./interfaces/IDataBuffer.sol";
import {DataVerifier} from "./DataVerifier.sol";
import {Layer4MetricEncoding} from "./Layer4MetricEncoding.sol";

/// @notice Gate L4-05 + L4-06 — publishes verified aggregates after buffer reveal; never calls Layer 2.
contract Layer4DataOracle is IDataOracle, Ownable {
    IDataBuffer public immutable dataBuffer;

    address public aggregator;

    /// @notice Gate L4-06 — when true, reads return last-known-good values with zero confidence.
    bool public degradedMode;

    mapping(bytes32 => AggregatedMetric) internal _latest;
    mapping(bytes32 => AggregatedMetric) internal _lastKnownGood;
    mapping(bytes32 => bool) internal _batchPublished;

    event AggregatorUpdated(address indexed aggregator);
    event DegradedModeUpdated(bool degraded);
    event MetricsPublished(bytes32 indexed batchId, bytes32[] metricIds);

    error OnlyAggregator();
    error BatchNotRevealed();
    error BatchAlreadyPublished();
    error LengthMismatch();
    error LeafMismatch();

    constructor(address initialOwner, address dataBuffer_) Ownable(initialOwner) {
        dataBuffer = IDataBuffer(dataBuffer_);
    }

    function setAggregator(address a) external onlyOwner {
        aggregator = a;
        emit AggregatorUpdated(a);
    }

    function setDegradedMode(bool d) external onlyOwner {
        degradedMode = d;
        emit DegradedModeUpdated(d);
    }

    modifier onlyAggregator() {
        if (msg.sender != aggregator) revert OnlyAggregator();
        _;
    }

    /// @notice Stores metrics after verifying each leaf against the revealed Merkle root, then consumes the batch.
    function publishBatchWithProofs(
        bytes32 batchId,
        AggregatedMetric[] calldata metrics,
        bytes32[] calldata leaves,
        bytes32[][] calldata proofs
    ) external onlyAggregator {
        if (_batchPublished[batchId]) revert BatchAlreadyPublished();
        if (!dataBuffer.isRevealed(batchId)) revert BatchNotRevealed();
        if (metrics.length != leaves.length || metrics.length != proofs.length) revert LengthMismatch();

        bytes32 root = dataBuffer.getMerkleRoot(batchId);
        bytes32[] memory ids = new bytes32[](metrics.length);

        for (uint256 i = 0; i < metrics.length; i++) {
            AggregatedMetric calldata m = metrics[i];
            if (leaves[i] != Layer4MetricEncoding.leafHashCalldata(m)) revert LeafMismatch();
            DataVerifier.requireLeaf(root, leaves[i], proofs[i]);
            _latest[m.metricId] = m;
            _lastKnownGood[m.metricId] = m;
            ids[i] = m.metricId;
        }

        _batchPublished[batchId] = true;
        dataBuffer.consume(batchId);
        emit MetricsPublished(batchId, ids);
    }

    /// @notice Fallback path when proofs are checked off-chain (still requires reveal + single publisher trust).
    function publishBatchTrusted(bytes32 batchId, AggregatedMetric[] calldata metrics) external onlyAggregator {
        if (_batchPublished[batchId]) revert BatchAlreadyPublished();
        if (!dataBuffer.isRevealed(batchId)) revert BatchNotRevealed();

        bytes32[] memory ids = new bytes32[](metrics.length);
        for (uint256 i = 0; i < metrics.length; i++) {
            AggregatedMetric calldata m = metrics[i];
            _latest[m.metricId] = m;
            _lastKnownGood[m.metricId] = m;
            ids[i] = m.metricId;
        }
        _batchPublished[batchId] = true;
        dataBuffer.consume(batchId);
        emit MetricsPublished(batchId, ids);
    }

    function getMetric(bytes32 metricId) external view override returns (AggregatedMetric memory m) {
        return _readMetric(metricId);
    }

    function getMetricBatch(bytes32[] calldata metricIds)
        external
        view
        override
        returns (AggregatedMetric[] memory out)
    {
        out = new AggregatedMetric[](metricIds.length);
        for (uint256 i = 0; i < metricIds.length; i++) {
            out[i] = _readMetric(metricIds[i]);
        }
    }

    function _readMetric(bytes32 metricId) private view returns (AggregatedMetric memory m) {
        if (degradedMode) {
            m = _lastKnownGood[metricId];
            m.confidenceScore = 0;
            return m;
        }
        m = _latest[metricId];
    }
}
