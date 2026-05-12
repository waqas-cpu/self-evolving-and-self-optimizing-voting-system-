// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";
import {Layer1Types} from "./Layer1Types.sol";

contract Layer1IdentityRegistry is Ownable {
    mapping(bytes32 => Layer1Types.IdentityRecord) public identityByCommitment;
    mapping(bytes32 => bool) public didSeen;
    mapping(bytes32 => bool) public providerNullifierSeen;
    mapping(bytes32 => uint256) public deviceEnrollmentCount;
    mapping(bytes32 => bool) public quarantined;

    uint16 public minReputationBps = 5000;
    uint256 public deviceEnrollmentLimit = 3;

    event IdentityEnrolled(bytes32 indexed commitment, bytes32 indexed didHash);
    event IdentityQuarantined(bytes32 indexed commitment, bytes32 reasonCode);
    event IdentityStateUpdated(bytes32 indexed commitment, Layer1Types.IdentityState state);

    error DuplicateIdentity();
    error ReputationTooLow();
    error InvalidProofSourceCount();
    error DeviceEnrollmentSpike();
    error SplitAttackDetected();
    error InvalidStateTransition();
    error UnknownIdentity();

    constructor(address initialOwner) Ownable(initialOwner) {}

    function enroll(
        Layer1Types.EnrollmentRequest calldata req,
        bytes32 uniqueNullifier
    ) external onlyOwner returns (bytes32 commitment) {
        if (didSeen[req.didHash]) revert DuplicateIdentity();
        if (req.reputationBps < minReputationBps) revert ReputationTooLow();
        if (req.providerNullifiers.length < 2) revert InvalidProofSourceCount();

        uint256 enrollCount = ++deviceEnrollmentCount[req.deviceFingerprint];
        if (enrollCount > deviceEnrollmentLimit) revert DeviceEnrollmentSpike();

        for (uint256 i; i < req.providerNullifiers.length; ++i) {
            bytes32 providerN = req.providerNullifiers[i];
            if (providerNullifierSeen[providerN]) revert SplitAttackDetected();
            providerNullifierSeen[providerN] = true;
        }

        commitment = keccak256(abi.encodePacked(uniqueNullifier));
        Layer1Types.IdentityRecord storage existing = identityByCommitment[commitment];
        if (existing.didHash != bytes32(0)) revert DuplicateIdentity();

        identityByCommitment[commitment] = Layer1Types.IdentityRecord({
            didHash: req.didHash,
            uniqueNullifier: uniqueNullifier,
            state: Layer1Types.IdentityState.ENROLLED,
            enrolledBlock: uint64(block.number),
            expiryBlock: uint64(block.number + 50_000)
        });
        didSeen[req.didHash] = true;
        emit IdentityEnrolled(commitment, req.didHash);
    }

    function setState(bytes32 commitment, Layer1Types.IdentityState newState) external onlyOwner {
        Layer1Types.IdentityRecord storage record = identityByCommitment[commitment];
        if (record.didHash == bytes32(0)) revert UnknownIdentity();

        Layer1Types.IdentityState oldState = record.state;
        bool valid = (oldState == Layer1Types.IdentityState.ENROLLED && newState == Layer1Types.IdentityState.ACTIVE)
            || (oldState == Layer1Types.IdentityState.ACTIVE && newState == Layer1Types.IdentityState.FLAGGED)
            || (oldState == Layer1Types.IdentityState.ACTIVE && newState == Layer1Types.IdentityState.REVOKED)
            || (oldState == Layer1Types.IdentityState.FLAGGED && newState == Layer1Types.IdentityState.REVOKED);
        if (!valid) revert InvalidStateTransition();

        record.state = newState;
        emit IdentityStateUpdated(commitment, newState);
    }

    function quarantine(bytes32 commitment, bytes32 reasonCode) external onlyOwner {
        quarantined[commitment] = true;
        emit IdentityQuarantined(commitment, reasonCode);
    }
}
