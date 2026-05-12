// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";
import {ILayer2AuditTrail} from "./interfaces/ILayer2AuditTrail.sol";

contract IdentityBinding is Ownable {
    enum IdentityStatus {
        VALID,
        EXPIRED,
        REVOKED,
        COMPROMISED
    }

    uint256 public constant MAX_PROOF_AGE = 1 days;
    mapping(bytes32 => address) public votingAccountByDid;
    mapping(address => bytes32) public didByVotingAccount;
    mapping(address => bool) public isVerified;
    mapping(address => bool) public isCompromised;
    mapping(bytes32 => bool) public revokedRegistry;
    mapping(bytes32 => uint256) public nonceByDid;
    mapping(bytes32 => uint256) public allocatedCreditsByDid;
    ILayer2AuditTrail public auditTrail;

    event IdentityVerified(bytes32 indexed didHash, address indexed votingAddress, uint256 voiceCreditAllocation, uint256 nonce);
    event IdentityInvalidated(bytes32 indexed didHash, uint256 frozenCredits, uint256 timestamp);

    error DuplicateDid();
    error InvalidProofAge();
    error RevokedIdentity();
    error CredentialMismatch();
    error UnknownIdentity();

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setAuditTrail(ILayer2AuditTrail trail) external onlyOwner {
        auditTrail = trail;
    }

    function verifyIdentity(
        bytes calldata,
        string calldata did,
        bytes32 credentialHash,
        uint256 timestamp,
        address votingAddress,
        bytes32 issuerPubKeyHash,
        uint256 voiceCreditAllocation
    ) external onlyOwner returns (IdentityStatus status, uint256 allocation, uint256 nonce) {
        bytes32 didHash = keccak256(bytes(did));
        if (block.timestamp > timestamp + MAX_PROOF_AGE) revert InvalidProofAge();
        if (revokedRegistry[didHash]) revert RevokedIdentity();
        if (credentialHash != keccak256(abi.encodePacked(didHash, issuerPubKeyHash))) revert CredentialMismatch();
        if (votingAccountByDid[didHash] != address(0)) revert DuplicateDid();

        votingAccountByDid[didHash] = votingAddress;
        didByVotingAccount[votingAddress] = didHash;
        isVerified[votingAddress] = true;
        nonce = ++nonceByDid[didHash];
        allocatedCreditsByDid[didHash] = voiceCreditAllocation;
        emit IdentityVerified(didHash, votingAddress, voiceCreditAllocation, nonce);
        _audit(
            keccak256("GATE_1_IDENTITY"),
            keccak256("VERIFY_IDENTITY"),
            didHash,
            true,
            ILayer2AuditTrail.Severity.INFO,
            keccak256(abi.encodePacked(votingAddress, voiceCreditAllocation, nonce))
        );
        return (IdentityStatus.VALID, voiceCreditAllocation, nonce);
    }

    function invalidateIdentity(string calldata did, uint256 frozenCredits) external onlyOwner returns (bool success, uint256 frozen) {
        bytes32 didHash = keccak256(bytes(did));
        address votingAddr = votingAccountByDid[didHash];
        if (votingAddr == address(0)) revert UnknownIdentity();
        revokedRegistry[didHash] = true;
        isVerified[votingAddr] = false;
        isCompromised[votingAddr] = true;
        emit IdentityInvalidated(didHash, frozenCredits, block.timestamp);
        _audit(
            keccak256("GATE_1_IDENTITY"),
            keccak256("INVALIDATE_IDENTITY"),
            didHash,
            true,
            ILayer2AuditTrail.Severity.HIGH,
            keccak256(abi.encodePacked(votingAddr, frozenCredits))
        );
        return (true, frozenCredits);
    }

    function isEligible(address voter) external view returns (bool) {
        return isVerified[voter] && !isCompromised[voter];
    }

    function _audit(
        bytes32 gateId,
        bytes32 actionId,
        bytes32 subjectId,
        bool success,
        ILayer2AuditTrail.Severity severity,
        bytes32 contextHash
    ) internal {
        if (address(auditTrail) == address(0)) return;
        auditTrail.recordGateEvent(gateId, actionId, subjectId, success, severity, contextHash);
    }
}
