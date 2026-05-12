// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Layer3Orchestrator} from "../contracts/Layer3Orchestrator.sol";
import {Layer3ModelRegistry} from "../contracts/Layer3ModelRegistry.sol";
import {Layer3FeedbackLedger} from "../contracts/Layer3FeedbackLedger.sol";
import {Layer3DataIngestionLib} from "../contracts/libraries/Layer3DataIngestionLib.sol";
import {Layer3KPILib} from "../contracts/libraries/Layer3KPILib.sol";
import {MockL2ParameterRegistry} from "./MockL2ParameterRegistry.sol";

interface Vm {
    function sign(uint256 privateKey, bytes32 digest)
        external
        pure
        returns (uint8 v, bytes32 r, bytes32 s);
    function addr(uint256 privateKey) external pure returns (address);
}

contract Layer3IntegrationTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    MockL2ParameterRegistry internal registry;
    Layer3ModelRegistry internal models;
    Layer3FeedbackLedger internal feedback;
    Layer3Orchestrator internal orch;

    uint256 internal pk1 = 0xA11;
    uint256 internal pk2 = 0xB22;
    uint256 internal pk3 = 0xC33;

    constructor() {
        registry = new MockL2ParameterRegistry();
        models = new Layer3ModelRegistry(address(this));
        feedback = new Layer3FeedbackLedger(address(this));
        orch = new Layer3Orchestrator(address(this), address(registry), address(models), 50);

        bytes32 vid = keccak256("model-v1");
        models.registerModelVersion(
            vid,
            keccak256("artifact"),
            keccak256("artifact"),
            bytes32(uint256(1)),
            bytes32(uint256(2))
        );
        models.activateModel(vid);

        orch.setOracle(vm.addr(pk1), true);
        orch.setOracle(vm.addr(pk2), true);
        orch.setOracle(vm.addr(pk3), true);
    }

    function _sign(bytes32 dataPayloadHash, uint256 observedAt, uint256 pk)
        internal
        view
        returns (bytes memory)
    {
        bytes32 inner = keccak256(abi.encodePacked(dataPayloadHash, observedAt));
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", inner));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function testConservativeFallbackWhenConfidenceLow() public {
        bytes32 dataPayloadHash = keccak256("payload");
        uint256 t = block.timestamp;
        Layer3DataIngestionLib.Attestation[3] memory atts;
        atts[0] = Layer3DataIngestionLib.Attestation({
            oracle: vm.addr(pk1),
            observedAt: t,
            payloadHash: dataPayloadHash,
            signature: _sign(dataPayloadHash, t, pk1)
        });
        atts[1] = Layer3DataIngestionLib.Attestation({
            oracle: vm.addr(pk2),
            observedAt: t,
            payloadHash: dataPayloadHash,
            signature: _sign(dataPayloadHash, t, pk2)
        });
        atts[2] = Layer3DataIngestionLib.Attestation({
            oracle: vm.addr(pk3),
            observedAt: t,
            payloadHash: dataPayloadHash,
            signature: _sign(dataPayloadHash, t, pk3)
        });

        // Healthy KPIs -> no aggressive moves -> conservative path (no registry proposals).
        Layer3KPILib.RawMetrics memory raw = Layer3KPILib.RawMetrics({
            actualVoters: 800,
            eligibleVoters: 1000,
            passedProposals: 5,
            totalProposals: 10,
            actualQuadraticCostWad: 5e17,
            theoreticalOptimalCostWad: 1e18,
            treasuryOutflowWad: 1e17,
            timeWindowWad: 1e18,
            creditsSpentWad: 5e17,
            creditsAllocatedWad: 1e18
        });

        string memory j =
            "This is a human-readable justification for Layer 5 veto review. It exceeds the minimum length required by GATE 6.";
        bytes memory justification = bytes(j);

        bytes32 vid = models.activeVersionId();
        uint256 proposalsBefore = registry.proposalCount();
        orch.executeEvolutionCycle(dataPayloadHash, t, t, atts, raw, 8 days, justification, vid);
        require(registry.proposalCount() == proposalsBefore, "no L2 proposals on conservative path");
    }

    function testHighApathyTriggersProposals() public {
        bytes32 dataPayloadHash = keccak256("payload-2");
        uint256 t = block.timestamp;
        Layer3DataIngestionLib.Attestation[3] memory atts;
        atts[0] = Layer3DataIngestionLib.Attestation({
            oracle: vm.addr(pk1),
            observedAt: t,
            payloadHash: dataPayloadHash,
            signature: _sign(dataPayloadHash, t, pk1)
        });
        atts[1] = Layer3DataIngestionLib.Attestation({
            oracle: vm.addr(pk2),
            observedAt: t,
            payloadHash: dataPayloadHash,
            signature: _sign(dataPayloadHash, t, pk2)
        });
        atts[2] = Layer3DataIngestionLib.Attestation({
            oracle: vm.addr(pk3),
            observedAt: t,
            payloadHash: dataPayloadHash,
            signature: _sign(dataPayloadHash, t, pk3)
        });

        // Isolate voter apathy (>0.5) so GATE 3 nudges quorum without tripping simulation stress heuristics.
        Layer3KPILib.RawMetrics memory raw = Layer3KPILib.RawMetrics({
            actualVoters: 100,
            eligibleVoters: 1000,
            passedProposals: 5,
            totalProposals: 10,
            actualQuadraticCostWad: 8e17,
            theoreticalOptimalCostWad: 1e18,
            treasuryOutflowWad: 1e17,
            timeWindowWad: 1e18,
            creditsSpentWad: 5e17,
            creditsAllocatedWad: 1e18
        });

        string memory j =
            "High apathy scenario justification for timelock broadcast and veto multisig review per integration gates specification text.";
        bytes memory justification = bytes(j);

        bytes32 vid = models.activeVersionId();
        uint256 before = registry.proposalCount();
        orch.executeEvolutionCycle(dataPayloadHash, t, t, atts, raw, 8 days, justification, vid);
        require(orch.lastCycleId() != bytes32(0), "cycle id");
        require(registry.proposalCount() > before, "expected at least one parameter proposal");
    }

    function testFeedbackWriter() public {
        feedback.setWriter(address(this), true);
        Layer3FeedbackLedger.TrainingDataPoint memory p = Layer3FeedbackLedger.TrainingDataPoint({
            modelVersionId: models.activeVersionId(),
            proposalCount: 3,
            predictionAccuracyWad: 75e16,
            avgVoterTurnout: 100,
            avgTimeToConsensus: 200,
            timestamp: block.timestamp,
            outlierFlagged: false,
            finalizedProposalRoot: keccak256("finalized")
        });
        feedback.captureFeedback(p);
        require(feedback.pointCount() == 1, "feedback count");
    }
}
