// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Layer1Types} from "../contracts/Layer1Types.sol";
import {Layer1Bridge} from "../contracts/Layer1Bridge.sol";
import {Layer1IdentityRegistry} from "../contracts/Layer1IdentityRegistry.sol";
import {Layer1VoiceCreditLedger} from "../contracts/Layer1VoiceCreditLedger.sol";
import {Layer1GateController} from "../contracts/Layer1GateController.sol";
import {MockZKVerifier} from "../contracts/mocks/MockZKVerifier.sol";

contract Layer1GateControllerTest {
    Layer1Bridge bridge;
    Layer1IdentityRegistry registry;
    Layer1VoiceCreditLedger ledger;
    MockZKVerifier verifier;
    Layer1GateController controller;

    constructor() {
        bridge = new Layer1Bridge(address(this), 100);
        registry = new Layer1IdentityRegistry(address(this));
        ledger = new Layer1VoiceCreditLedger(address(this));
        verifier = new MockZKVerifier();
        controller = new Layer1GateController(address(this), registry, ledger, bridge, verifier);

        registry.transferOwnership(address(controller));
        ledger.transferOwnership(address(controller));
        bridge.transferOwnership(address(controller));

        controller.setTrustedIssuer(address(this), true);
    }

    function _assertEq(uint256 a, uint256 b) internal pure {
        require(a == b, "assert eq failed");
    }

    function _assertTrue(bool ok) internal pure {
        require(ok, "assert true failed");
    }

    function _assertFalse(bool ok) internal pure {
        require(!ok, "assert false failed");
    }

    function _buildReq(
        string memory didSeed,
        string memory bioSeed,
        string memory deviceSeed,
        string memory pA,
        string memory pB
    ) internal view returns (Layer1Types.EnrollmentRequest memory req) {
        req.didHash = keccak256(bytes(didSeed));
        req.biometricNullifier = keccak256(bytes(bioSeed));
        req.deviceFingerprint = keccak256(bytes(deviceSeed));
        req.timestamp = uint64(block.timestamp);
        req.reputationBps = 9000;
        req.providerNullifiers = new bytes32[](2);
        req.providerNullifiers[0] = keccak256(bytes(pA));
        req.providerNullifiers[1] = keccak256(bytes(pB));
        req.zkProof = hex"01";
    }

    function testProcessIdentityAndDeductVoteCost() external {
        Layer1Types.EnrollmentRequest memory req;
        req.didHash = keccak256("did:example:alice");
        req.biometricNullifier = keccak256("bio");
        req.deviceFingerprint = keccak256("device");
        req.timestamp = uint64(block.timestamp);
        req.reputationBps = 9000;
        req.providerNullifiers = new bytes32[](2);
        req.providerNullifiers[0] = keccak256("provider-a");
        req.providerNullifiers[1] = keccak256("provider-b");
        req.zkProof = hex"01";

        bytes32 commitment = controller.processIdentity(req, address(this), 1, 100);
        _assertEq(ledger.balances(commitment), 100);

        uint256[] memory votes = new uint256[](2);
        votes[0] = 2;
        votes[1] = 1;
        controller.processVoteEntry(
            commitment,
            hex"02",
            votes,
            keccak256("proposal-1"),
            commitment,
            keccak256("safe-metadata")
        );
        _assertEq(ledger.balances(commitment), 95);
    }

    function testCompromiseInterruptFreezesCredits() external {
        Layer1Types.EnrollmentRequest memory req = _buildReq(
            "did:example:bob", "bio-b", "device-b", "provider-c", "provider-d"
        );

        bytes32 commitment = controller.processIdentity(req, address(this), 1, 50);
        controller.compromiseAndInvalidate(commitment, 1);
        _assertEq(ledger.balances(commitment), 0);
        _assertTrue(bridge.isCommitmentRevoked(commitment));
    }

    function testRejectDuplicateDid() external {
        Layer1Types.EnrollmentRequest memory req = _buildReq(
            "did:example:dup", "bio-dup", "device-dup", "provider-e", "provider-f"
        );
        controller.processIdentity(req, address(this), 1, 20);

        (bool ok, ) = address(controller).call(
            abi.encodeWithSelector(
                controller.processIdentity.selector,
                req,
                address(this),
                uint64(1),
                uint256(20)
            )
        );
        _assertFalse(ok);
    }

    function testRejectInvalidIssuer() external {
        Layer1Types.EnrollmentRequest memory req = _buildReq(
            "did:example:issuer", "bio-issuer", "device-issuer", "provider-g", "provider-h"
        );
        address badIssuer = address(0xBEEF);
        (bool ok, ) = address(controller).call(
            abi.encodeWithSelector(
                controller.processIdentity.selector,
                req,
                badIssuer,
                uint64(1),
                uint256(20)
            )
        );
        _assertFalse(ok);
    }

    function testRejectInvalidEnrollmentProof() external {
        verifier.setEnrollmentPass(false);
        Layer1Types.EnrollmentRequest memory req = _buildReq(
            "did:example:badproof", "bio-badproof", "device-badproof", "provider-i", "provider-j"
        );
        (bool ok, ) = address(controller).call(
            abi.encodeWithSelector(
                controller.processIdentity.selector,
                req,
                address(this),
                uint64(1),
                uint256(20)
            )
        );
        _assertFalse(ok);
    }

    function testRejectInvalidBindingProof() external {
        Layer1Types.EnrollmentRequest memory req = _buildReq(
            "did:example:binding", "bio-binding", "device-binding", "provider-k", "provider-l"
        );
        bytes32 commitment = controller.processIdentity(req, address(this), 1, 20);
        verifier.setBindingPass(false);

        uint256[] memory votes = new uint256[](1);
        votes[0] = 1;
        (bool ok, ) = address(controller).call(
            abi.encodeWithSelector(
                controller.processVoteEntry.selector,
                commitment,
                hex"02",
                votes,
                keccak256("proposal-bind"),
                commitment,
                keccak256("safe-metadata")
            )
        );
        _assertFalse(ok);
    }

    function testInvariantUniquenessDistinctEnrollmentsYieldDistinctCommitments() external {
        Layer1Types.EnrollmentRequest memory r1 =
            _buildReq("did:example:u1", "bio-u1", "device-u1", "provider-u1a", "provider-u1b");
        Layer1Types.EnrollmentRequest memory r2 =
            _buildReq("did:example:u2", "bio-u2", "device-u2", "provider-u2a", "provider-u2b");

        bytes32 c1 = controller.processIdentity(r1, address(this), 1, 10);
        bytes32 c2 = controller.processIdentity(r2, address(this), 1, 10);
        require(c1 != c2, "invariant broken: commitments must be unique");
    }

    function testInvariantRevokedCommitmentHasZeroCreditsAndCannotVote() external {
        Layer1Types.EnrollmentRequest memory req = _buildReq(
            "did:example:inv-revoke", "bio-inv-revoke", "device-inv-revoke", "provider-ra", "provider-rb"
        );
        bytes32 commitment = controller.processIdentity(req, address(this), 1, 30);
        controller.compromiseAndInvalidate(commitment, 99);

        _assertEq(ledger.balances(commitment), 0);
        _assertTrue(bridge.isCommitmentRevoked(commitment));

        uint256[] memory votes = new uint256[](1);
        votes[0] = 1;
        (bool ok, ) = address(controller).call(
            abi.encodeWithSelector(
                controller.processVoteEntry.selector,
                commitment,
                hex"02",
                votes,
                keccak256("proposal-revoked"),
                commitment,
                keccak256("safe-metadata")
            )
        );
        _assertFalse(ok);
    }
}
