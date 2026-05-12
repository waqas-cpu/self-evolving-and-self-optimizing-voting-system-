// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";
import {Layer1Types} from "./Layer1Types.sol";
import {IZKVerifier} from "./interfaces/IZKVerifier.sol";
import {Layer1IdentityRegistry} from "./Layer1IdentityRegistry.sol";
import {Layer1VoiceCreditLedger} from "./Layer1VoiceCreditLedger.sol";
import {Layer1Bridge} from "./Layer1Bridge.sol";

contract Layer1GateController is Ownable {
    Layer1IdentityRegistry public immutable registry;
    Layer1VoiceCreditLedger public immutable ledger;
    Layer1Bridge public immutable bridge;
    IZKVerifier public verifier;

    mapping(address => bool) public trustedIssuers;
    mapping(bytes32 => bool) public compromised;

    event GatePassed(bytes32 indexed gateId, bytes32 indexed commitment, bytes32 ruleId);
    event GateFailed(bytes32 indexed gateId, bytes32 indexed commitment, bytes32 ruleId, bytes32 failureMode);

    error UntrustedIssuer();
    error InvalidZKProof();
    error CompromisedIdentity();
    error DirectIdentityVoteLinkage();

    constructor(
        address initialOwner,
        Layer1IdentityRegistry _registry,
        Layer1VoiceCreditLedger _ledger,
        Layer1Bridge _bridge,
        IZKVerifier _verifier
    ) Ownable(initialOwner) {
        registry = _registry;
        ledger = _ledger;
        bridge = _bridge;
        verifier = _verifier;
    }

    function setTrustedIssuer(address issuer, bool trusted) external onlyOwner {
        trustedIssuers[issuer] = trusted;
    }

    function setVerifier(IZKVerifier newVerifier) external onlyOwner {
        verifier = newVerifier;
    }

    function processIdentity(
        Layer1Types.EnrollmentRequest calldata req,
        address issuer,
        uint64 epochId,
        uint256 initialCredits
    ) external onlyOwner returns (bytes32 commitment) {
        // G1: enrollment constraints
        if (!trustedIssuers[issuer]) revert UntrustedIssuer();
        _emitPass("L1-G1", bytes32(0), "G1-R3");

        // G2: zk verification gate
        bytes32[] memory inputs = new bytes32[](3);
        inputs[0] = req.didHash;
        inputs[1] = req.biometricNullifier;
        inputs[2] = keccak256(abi.encodePacked(req.providerNullifiers.length));
        if (!verifier.verifyEnrollmentProof(req.zkProof, inputs)) revert InvalidZKProof();
        _emitPass("L1-G2", bytes32(0), "G2-R1");

        // G3: sybil uniqueness gate via registry checks
        bytes32 uniqueNullifier = keccak256(abi.encodePacked(req.didHash, req.biometricNullifier));
        commitment = registry.enroll(req, uniqueNullifier);
        _emitPass("L1-G3", commitment, "G3-R1");

        // G6: bind credits for current epoch
        ledger.allocateCredits(commitment, initialCredits, epochId);
        registry.setState(commitment, Layer1Types.IdentityState.ACTIVE);
        bridge.emitCredentialMinted(abi.encode(commitment, initialCredits, epochId));
        bridge.setActiveIdentityCount(bridge.getActiveIdentityCount() + 1);
        _emitPass("L1-G6", commitment, "G6-R1");
    }

    function processVoteEntry(
        bytes32 commitment,
        bytes calldata zkBindingProof,
        uint256[] calldata voteVector,
        bytes32 proposalId,
        bytes32 identityCommitmentInPayload,
        bytes32 metadataHash
    ) external onlyOwner {
        // G4: anonymity preservation checks
        if (identityCommitmentInPayload == bytes32(0)) revert DirectIdentityVoteLinkage();
        if (metadataHash == bytes32(0)) {
            _emitFail("L1-G4", commitment, "G4-R4", "SANITIZE");
            return;
        }
        _emitPass("L1-G4", commitment, "G4-R1");

        // G5 interrupt gate
        if (compromised[commitment] || bridge.isCommitmentRevoked(commitment)) revert CompromisedIdentity();

        // G6 verify binding proof and deduct quadratic cost
        bytes32[] memory inputs = new bytes32[](1);
        inputs[0] = commitment;
        if (!verifier.verifyBindingProof(zkBindingProof, inputs)) revert InvalidZKProof();
        ledger.deductQuadraticCost(commitment, voteVector, proposalId);
        _emitPass("L1-G6", commitment, "G6-R4");
    }

    function compromiseAndInvalidate(bytes32 commitment, uint8 reasonCode) external onlyOwner {
        compromised[commitment] = true;
        registry.setState(commitment, Layer1Types.IdentityState.FLAGGED);
        registry.setState(commitment, Layer1Types.IdentityState.REVOKED);
        ledger.freeze(commitment);
        bridge.emitCreditInvalidated(commitment, abi.encode(commitment, reasonCode, block.number));
        _emitFail("L1-G5", commitment, "G5-R1", "HALT");
    }

    function _emitPass(string memory gate, bytes32 commitment, string memory rule) internal {
        emit GatePassed(keccak256(bytes(gate)), commitment, keccak256(bytes(rule)));
    }

    function _emitFail(string memory gate, bytes32 commitment, string memory rule, string memory mode) internal {
        emit GateFailed(keccak256(bytes(gate)), commitment, keccak256(bytes(rule)), keccak256(bytes(mode)));
    }
}
