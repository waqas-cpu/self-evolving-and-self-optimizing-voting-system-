// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ParameterRegistry} from "../contracts/ParameterRegistry.sol";
import {IdentityBinding} from "../contracts/IdentityBinding.sol";
import {VoiceCreditLedger} from "../contracts/VoiceCreditLedger.sol";
import {ProposalLifecycle} from "../contracts/ProposalLifecycle.sol";
import {Layer2AuditTrail} from "../contracts/Layer2AuditTrail.sol";
import {ILayer2AuditTrail} from "../contracts/interfaces/ILayer2AuditTrail.sol";
import {MockTarget} from "../contracts/mocks/MockTarget.sol";

interface Vm {
    function roll(uint256) external;
}

contract Layer2AuditTrailTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    ParameterRegistry params;
    IdentityBinding identity;
    VoiceCreditLedger ledger;
    ProposalLifecycle lifecycle;
    Layer2AuditTrail audit;
    MockTarget target;

    address voter = address(this);

    function _assertTrue(bool v) internal pure {
        require(v, "assert true failed");
    }

    function _assertEq(bytes32 a, bytes32 b) internal pure {
        require(a == b, "assert bytes32 eq failed");
    }

    function _assertEqU(uint256 a, uint256 b) internal pure {
        require(a == b, "assert uint eq failed");
    }

    constructor() {
        params = new ParameterRegistry(address(this));
        identity = new IdentityBinding(address(this));
        ledger = new VoiceCreditLedger(address(this), params);
        lifecycle = new ProposalLifecycle(address(this), params, identity, ledger);
        audit = new Layer2AuditTrail(address(this));
        target = new MockTarget();

        ledger.setTrustedCaller(address(this), true);
        ledger.setTrustedCaller(address(lifecycle), true);

        audit.setReporter(address(identity), true);
        audit.setReporter(address(ledger), true);
        audit.setReporter(address(lifecycle), true);
        audit.setReporter(address(params), true);

        identity.setAuditTrail(audit);
        ledger.setAuditTrail(audit);
        lifecycle.setAuditTrail(audit);
        params.setAuditTrail(audit);

        params.transferOwnership(address(lifecycle));
    }

    function _verifyAndFund(string memory did, uint256 credits) internal {
        bytes32 didHash = keccak256(bytes(did));
        bytes32 issuerKey = keccak256("issuer");
        bytes32 credential = keccak256(abi.encodePacked(didHash, issuerKey));
        identity.verifyIdentity(hex"01", did, credential, block.timestamp, voter, issuerKey, credits);
        ledger.allocateCredits(voter, credits);
    }

    function testAuditEventSchemaForIdentityAndCreditGate() external {
        uint256 beforeCount = audit.recordCount();
        _verifyAndFund("did:ethr:0xa1", 300);
        uint256 afterCount = audit.recordCount();

        // Workflow minimum: verifyIdentity + allocateCredits = 2 events
        _assertTrue(afterCount >= beforeCount + 2);

        Layer2AuditTrail.AuditRecord memory r0 = audit.getRecord(beforeCount);
        _assertEq(r0.gateId, keccak256("GATE_1_IDENTITY"));
        _assertEq(r0.actionId, keccak256("VERIFY_IDENTITY"));
        _assertTrue(r0.success);

        Layer2AuditTrail.AuditRecord memory r1 = audit.getRecord(beforeCount + 1);
        _assertEq(r1.gateId, keccak256("GATE_2_VOICE_CREDIT"));
        _assertEq(r1.actionId, keccak256("ALLOCATE_CREDITS"));
        _assertTrue(r1.success);
    }

    function testAuditEventSchemaForProposalWorkflow() external {
        _verifyAndFund("did:ethr:0xb2", 400);
        uint256 beforeCount = audit.recordCount();

        bytes32[] memory opts = new bytes32[](2);
        opts[0] = keccak256("FOR");
        opts[1] = keccak256("AGAINST");
        bytes memory payload = abi.encodeWithSelector(target.setNumber.selector, 7);

        (bytes32 proposalId, uint256 startBlock, uint256 endBlock) =
            lifecycle.submitProposal("did:ethr:0xb2", keccak256("p2"), payload, address(target), opts, "ipfs://audit");
        vm.roll(startBlock + 1);
        lifecycle.activateProposal(proposalId);

        uint256[] memory dist = new uint256[](2);
        dist[0] = 4;
        dist[1] = 0;
        int8[] memory signs = new int8[](2);
        signs[0] = 1;
        signs[1] = -1;
        lifecycle.castVote("did:ethr:0xb2", proposalId, dist, signs);
        vm.roll(endBlock + 1);
        lifecycle.tallyVotes(proposalId);
        lifecycle.executeProposal(proposalId);

        uint256 afterCount = audit.recordCount();
        // Workflow minimum:
        // SUBMIT + ACTIVATE + LOCK + CAST + TALLY + EXECUTE = 6
        _assertTrue(afterCount >= beforeCount + 6);

        Layer2AuditTrail.AuditRecord memory s = audit.getRecord(beforeCount);
        _assertEq(s.gateId, keccak256("GATE_3_PROPOSAL"));
        _assertEq(s.actionId, keccak256("SUBMIT_PROPOSAL"));

        Layer2AuditTrail.AuditRecord memory a = audit.getRecord(beforeCount + 1);
        _assertEq(a.actionId, keccak256("ACTIVATE_PROPOSAL"));

        Layer2AuditTrail.AuditRecord memory l = audit.getRecord(beforeCount + 2);
        _assertEq(l.gateId, keccak256("GATE_2_VOICE_CREDIT"));
        _assertEq(l.actionId, keccak256("LOCK_CREDITS"));

        Layer2AuditTrail.AuditRecord memory c = audit.getRecord(beforeCount + 3);
        _assertEq(c.gateId, keccak256("GATE_3_PROPOSAL"));
        _assertEq(c.actionId, keccak256("CAST_VOTE"));

        Layer2AuditTrail.AuditRecord memory t = audit.getRecord(beforeCount + 4);
        _assertEq(t.actionId, keccak256("TALLY_VOTES"));

        Layer2AuditTrail.AuditRecord memory e = audit.getRecord(beforeCount + 5);
        _assertEq(e.actionId, keccak256("EXECUTE_PROPOSAL"));
    }

    function testAuditEventSchemaForEmergencyWorkflowMinCount() external {
        uint256 beforeCount = audit.recordCount();
        lifecycle.triggerEmergencyStop(keccak256("audit-incident"));
        lifecycle.liftEmergencyStop(keccak256("audit-resolution"));
        uint256 afterCount = audit.recordCount();

        // Minimum from lifecycle+parameter reset:
        // TRIGGER_EMERGENCY_STOP + SAFE_MODE_RESET + LIFT_EMERGENCY_STOP = 3
        _assertTrue(afterCount >= beforeCount + 3);

        Layer2AuditTrail.AuditRecord memory r0 = audit.getRecord(beforeCount);
        Layer2AuditTrail.AuditRecord memory r1 = audit.getRecord(beforeCount + 1);
        Layer2AuditTrail.AuditRecord memory r2 = audit.getRecord(beforeCount + 2);

        _assertEq(r0.gateId, keccak256("GATE_6_EMERGENCY"));
        _assertEq(r0.actionId, keccak256("SAFE_MODE_RESET"));
        _assertEq(r1.actionId, keccak256("TRIGGER_EMERGENCY_STOP"));
        _assertEq(r2.actionId, keccak256("LIFT_EMERGENCY_STOP"));
        _assertEqU(uint256(r0.severity), uint256(ILayer2AuditTrail.Severity.CRITICAL));
    }
}
