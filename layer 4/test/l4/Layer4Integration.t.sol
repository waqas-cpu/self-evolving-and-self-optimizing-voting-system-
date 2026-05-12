// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DataBuffer} from "../../contracts/l4/DataBuffer.sol";
import {Layer4DataOracle} from "../../contracts/l4/Layer4DataOracle.sol";
import {IDataOracle} from "../../contracts/l4/interfaces/IDataOracle.sol";
import {TestMerkle3} from "./TestMerkle3.sol";

interface Vm {
    function warp(uint256 ts) external;
}

contract Layer4IntegrationTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function testPublishAfterRevealWithMerkleProofs() public {
        DataBuffer buf = new DataBuffer(address(this));
        Layer4DataOracle oracle = new Layer4DataOracle(address(this), address(buf));
        buf.setConsumer(address(oracle));
        oracle.setAggregator(address(this));

        IDataOracle.AggregatedMetric[3] memory metrics;
        metrics[0] = IDataOracle.AggregatedMetric({
            metricId: keccak256("TOKEN_PRICE"),
            value: 2_000e8,
            confidenceScore: 9500,
            freshnessScore: 9900,
            blockHeight: 1,
            aggregationProof: bytes32(uint256(1)),
            sourceCount: 3
        });
        metrics[1] = IDataOracle.AggregatedMetric({
            metricId: keccak256("TREASURY_VEL"),
            value: 1e18,
            confidenceScore: 9000,
            freshnessScore: 9800,
            blockHeight: 1,
            aggregationProof: bytes32(uint256(2)),
            sourceCount: 3
        });
        metrics[2] = IDataOracle.AggregatedMetric({
            metricId: keccak256("TURNOUT"),
            value: 7200,
            confidenceScore: 9200,
            freshnessScore: 9700,
            blockHeight: 1,
            aggregationProof: bytes32(uint256(3)),
            sourceCount: 3
        });

        (bytes32 root, bytes32[3] memory leaves, bytes32[][] memory proofs) = TestMerkle3.tree(metrics);
        bytes32 batchId = keccak256("integration-batch");
        buf.commit(batchId, root, 3);

        (,, uint256 revealAt,,,,) = buf.getBatch(batchId);
        vm.warp(revealAt + 1);
        buf.reveal(batchId);

        IDataOracle.AggregatedMetric[] memory batch = new IDataOracle.AggregatedMetric[](3);
        batch[0] = metrics[0];
        batch[1] = metrics[1];
        batch[2] = metrics[2];

        bytes32[] memory leafArr = new bytes32[](3);
        leafArr[0] = leaves[0];
        leafArr[1] = leaves[1];
        leafArr[2] = leaves[2];

        oracle.publishBatchWithProofs(batchId, batch, leafArr, proofs);

        IDataOracle.AggregatedMetric memory g = oracle.getMetric(metrics[0].metricId);
        require(g.value == metrics[0].value && g.confidenceScore == metrics[0].confidenceScore, "metric");
        require(buf.isConsumed(batchId), "consumed");
    }

    function testDegradedModeZeroConfidence() public {
        DataBuffer buf = new DataBuffer(address(this));
        Layer4DataOracle oracle = new Layer4DataOracle(address(this), address(buf));
        buf.setConsumer(address(oracle));
        oracle.setAggregator(address(this));

        IDataOracle.AggregatedMetric[3] memory metrics;
        metrics[0] = IDataOracle.AggregatedMetric({
            metricId: keccak256("DEG"),
            value: 100,
            confidenceScore: 8800,
            freshnessScore: 9000,
            blockHeight: 2,
            aggregationProof: bytes32(uint256(9)),
            sourceCount: 3
        });
        metrics[1] = IDataOracle.AggregatedMetric({
            metricId: keccak256("DEG2"),
            value: 200,
            confidenceScore: 8700,
            freshnessScore: 8900,
            blockHeight: 2,
            aggregationProof: bytes32(uint256(8)),
            sourceCount: 3
        });
        metrics[2] = IDataOracle.AggregatedMetric({
            metricId: keccak256("DEG3"),
            value: 300,
            confidenceScore: 8600,
            freshnessScore: 8800,
            blockHeight: 2,
            aggregationProof: bytes32(uint256(7)),
            sourceCount: 3
        });

        (bytes32 root, bytes32[3] memory leaves, bytes32[][] memory proofs) = TestMerkle3.tree(metrics);
        bytes32 batchId = keccak256("deg-batch");
        buf.commit(batchId, root, 3);
        (,, uint256 revealAt,,,,) = buf.getBatch(batchId);
        vm.warp(revealAt + 1);
        buf.reveal(batchId);

        IDataOracle.AggregatedMetric[] memory batch = new IDataOracle.AggregatedMetric[](3);
        batch[0] = metrics[0];
        batch[1] = metrics[1];
        batch[2] = metrics[2];
        bytes32[] memory leafArr = new bytes32[](3);
        leafArr[0] = leaves[0];
        leafArr[1] = leaves[1];
        leafArr[2] = leaves[2];

        oracle.publishBatchWithProofs(batchId, batch, leafArr, proofs);

        oracle.setDegradedMode(true);
        IDataOracle.AggregatedMetric memory out = oracle.getMetric(metrics[0].metricId);
        require(out.confidenceScore == 0, "degraded confidence");
        require(out.value == metrics[0].value, "value preserved");
    }
}
