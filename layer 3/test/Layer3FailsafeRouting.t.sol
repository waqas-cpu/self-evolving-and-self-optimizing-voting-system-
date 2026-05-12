// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Layer3Orchestrator} from "../contracts/Layer3Orchestrator.sol";
import {Layer3ModelRegistry} from "../contracts/Layer3ModelRegistry.sol";
import {Layer3DataIngestionLib} from "../contracts/libraries/Layer3DataIngestionLib.sol";
import {Layer3KPILib} from "../contracts/libraries/Layer3KPILib.sol";
import {MockL2ParameterRegistry} from "./MockL2ParameterRegistry.sol";
import {MockLayer5Timelock} from "./MockLayer5Timelock.sol";

interface Vm {
    function sign(uint256 privateKey, bytes32 digest)
        external
        pure
        returns (uint8 v, bytes32 r, bytes32 s);
    function addr(uint256 privateKey) external pure returns (address);
}

/// @notice Ensures Layer 3 routes parameter updates through Layer 5 when `setTimelock` is configured.
contract Layer3FailsafeRoutingTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    MockL2ParameterRegistry internal registry;
    Layer3ModelRegistry internal models;
    Layer3Orchestrator internal orch;
    MockLayer5Timelock internal tl;

    uint256 internal pk1 = 0xA11;
    uint256 internal pk2 = 0xB22;
    uint256 internal pk3 = 0xC33;

    constructor() {
        registry = new MockL2ParameterRegistry();
        models = new Layer3ModelRegistry(address(this));
        orch = new Layer3Orchestrator(address(this), address(registry), address(models), 50);
        tl = new MockLayer5Timelock();

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
        orch.setTimelock(address(tl));
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

    function testHighApathyQueuesViaLayer5NotL2() public {
        bytes32 dataPayloadHash = keccak256("payload-failsafe");
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
        uint256 l2Before = registry.proposalCount();
        uint256 tlBefore = tl.queueCount();

        orch.executeEvolutionCycle(dataPayloadHash, t, t, atts, raw, 8 days, justification, vid);

        require(registry.proposalCount() == l2Before, "L2 propose must not run when timelock wired");
        require(tl.queueCount() > tlBefore, "Layer 5 timelock must receive queueAdjustment");
        (uint256 vd, uint256 qt,,,,) = tl.lastQueued();
        require(vd != 0 && qt != 0, "queued snapshot populated");
    }
}
