// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";
import {ParameterRegistry} from "./ParameterRegistry.sol";
import {QuadraticMath} from "./libraries/QuadraticMath.sol";
import {IdentityBinding} from "./IdentityBinding.sol";
import {VoiceCreditLedger} from "./VoiceCreditLedger.sol";
import {ILayer2AuditTrail} from "./interfaces/ILayer2AuditTrail.sol";

contract ProposalLifecycle is Ownable {
    using QuadraticMath for uint256[];

    enum ProposalStatus {
        DRAFT,
        SUBMITTED,
        ACTIVE,
        TALLIED,
        EXECUTED,
        REJECTED,
        EXECUTION_FAILED,
        EXPIRED
    }

    struct Proposal {
        bytes32 id;
        address proposer;
        bytes32 proposalHash;
        bytes executionPayload;
        address target;
        bytes32[] votingOptions;
        string metadataURI;
        uint256 votingStartBlock;
        uint256 votingEndBlock;
        ProposalStatus status;
        bool quorumMet;
        uint256 winningOption;
    }

    struct VoteReceipt {
        bool hasVoted;
        uint256 creditsConsumed;
        uint256[] voteDistribution;
        int256[] votePowers;
    }

    ParameterRegistry public immutable params;
    IdentityBinding public immutable identity;
    VoiceCreditLedger public immutable ledger;
    mapping(bytes32 => Proposal) public proposals;
    mapping(bytes32 => mapping(address => VoteReceipt)) public votes;
    mapping(bytes32 => int256[]) public tallies;
    mapping(bytes32 => address[]) public voters;
    bool public safeMode;
    mapping(bytes4 => bool) public restrictedSelectors;
    ILayer2AuditTrail public auditTrail;

    event ProposalSubmitted(bytes32 indexed proposalId, bytes32 indexed proposerDidHash, uint256 votingStartBlock, uint256 votingEndBlock);
    event VoteCast(bytes32 indexed voteReceipt, bytes32 indexed proposalId, bytes32 indexed voterDidHash, uint256 creditsConsumed);
    event VotesTallied(bytes32 indexed proposalId, int256[] results, bool quorumMet, uint256 winningOption);
    event ProposalExecuted(bytes32 indexed proposalId, bytes executionResult, uint256 timestamp);
    event EmergencyStopTriggered(bytes32 reasonHash, uint256 timestamp);
    event EmergencyStopLifted(bytes32 resolutionHash, uint256 timestamp);

    error NotEligible();
    error InvalidProposalState();
    error InvalidWindow();
    error AlreadyVoted();
    error InvalidVoteVector();
    error InsufficientCredits();
    error RestrictedPayload();
    error SafeModeActive();

    constructor(address initialOwner, ParameterRegistry _params, IdentityBinding _identity, VoiceCreditLedger _ledger)
        Ownable(initialOwner)
    {
        params = _params;
        identity = _identity;
        ledger = _ledger;
        restrictedSelectors[bytes4(keccak256("submitProposal(string,bytes32,bytes,address,bytes32[],string)"))] = true;
        restrictedSelectors[bytes4(keccak256("castVote(string,bytes32,uint256[],int8[])"))] = true;
        restrictedSelectors[bytes4(keccak256("executeProposal(bytes32)"))] = true;
    }

    modifier notSafeMode() {
        if (safeMode) revert SafeModeActive();
        _;
    }

    function setAuditTrail(ILayer2AuditTrail trail) external onlyOwner {
        auditTrail = trail;
    }

    function submitProposal(
        string calldata proposerDid,
        bytes32 proposalHash,
        bytes calldata executionPayload,
        address target,
        bytes32[] calldata votingOptions,
        string calldata metadataURI
    ) external notSafeMode returns (bytes32 proposalId, uint256 votingStartBlock, uint256 votingEndBlock) {
        if (!identity.isEligible(msg.sender)) revert NotEligible();
        if (votingOptions.length < 2 || votingOptions.length > 10) revert InvalidVoteVector();
        if (executionPayload.length < 4) revert RestrictedPayload();
        bytes4 sel = bytes4(executionPayload[:4]);
        if (restrictedSelectors[sel]) revert RestrictedPayload();

        votingStartBlock = block.number + params.values(ParameterRegistry.ParamKey.SUBMISSION_DELAY);
        votingEndBlock = votingStartBlock + params.values(ParameterRegistry.ParamKey.VOTING_DURATION);
        proposalId = keccak256(abi.encodePacked(proposerDid, proposalHash, executionPayload, block.timestamp, block.number));

        Proposal storage p = proposals[proposalId];
        p.id = proposalId;
        p.proposer = msg.sender;
        p.proposalHash = proposalHash;
        p.executionPayload = executionPayload;
        p.target = target;
        p.metadataURI = metadataURI;
        p.votingStartBlock = votingStartBlock;
        p.votingEndBlock = votingEndBlock;
        p.status = ProposalStatus.SUBMITTED;
        for (uint256 i; i < votingOptions.length; ++i) p.votingOptions.push(votingOptions[i]);
        tallies[proposalId] = new int256[](votingOptions.length);
        emit ProposalSubmitted(proposalId, keccak256(bytes(proposerDid)), votingStartBlock, votingEndBlock);
        _audit(
            keccak256("GATE_3_PROPOSAL"),
            keccak256("SUBMIT_PROPOSAL"),
            proposalId,
            true,
            ILayer2AuditTrail.Severity.INFO,
            keccak256(abi.encodePacked(msg.sender, target, votingOptions.length))
        );
    }

    function activateProposal(bytes32 proposalId) external {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.SUBMITTED) revert InvalidProposalState();
        if (block.number < p.votingStartBlock) revert InvalidWindow();
        p.status = ProposalStatus.ACTIVE;
        _audit(
            keccak256("GATE_3_PROPOSAL"),
            keccak256("ACTIVATE_PROPOSAL"),
            proposalId,
            true,
            ILayer2AuditTrail.Severity.INFO,
            keccak256(abi.encodePacked(p.votingStartBlock, p.votingEndBlock))
        );
    }

    function castVote(string calldata voterDid, bytes32 proposalId, uint256[] calldata voteDistribution, int8[] calldata voteSigns)
        external
        notSafeMode
        returns (bytes32 voteReceipt, uint256 creditsConsumed, uint256 remainingCredits)
    {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.ACTIVE) revert InvalidProposalState();
        if (block.number < p.votingStartBlock || block.number > p.votingEndBlock) revert InvalidWindow();
        if (!identity.isEligible(msg.sender)) revert NotEligible();

        VoteReceipt storage existing = votes[proposalId][msg.sender];
        if (existing.hasVoted) revert AlreadyVoted();
        if (voteDistribution.length != p.votingOptions.length || voteSigns.length != p.votingOptions.length) revert InvalidVoteVector();

        (creditsConsumed,) = QuadraticMath.calculateQuadraticCost(voteDistribution);
        if (creditsConsumed > ledger.availableCredits(msg.sender)) revert InsufficientCredits();

        ledger.lockCredits(msg.sender, proposalId, creditsConsumed);
        int256[] memory powers = QuadraticMath.computeSignedPowers(voteDistribution, voteSigns);
        for (uint256 i; i < powers.length; ++i) {
            tallies[proposalId][i] += powers[i];
        }

        existing.hasVoted = true;
        existing.creditsConsumed = creditsConsumed;
        existing.voteDistribution = voteDistribution;
        existing.votePowers = powers;
        voters[proposalId].push(msg.sender);

        voteReceipt = keccak256(abi.encodePacked(proposalId, msg.sender, block.number));
        remainingCredits = ledger.availableCredits(msg.sender);
        emit VoteCast(voteReceipt, proposalId, keccak256(bytes(voterDid)), creditsConsumed);
        _audit(
            keccak256("GATE_3_PROPOSAL"),
            keccak256("CAST_VOTE"),
            proposalId,
            true,
            ILayer2AuditTrail.Severity.INFO,
            keccak256(abi.encodePacked(msg.sender, creditsConsumed, voteReceipt))
        );
    }

    function tallyVotes(bytes32 proposalId) external returns (int256[] memory results, uint256 totalParticipation, bool quorumMet, uint256 winningOption) {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.ACTIVE) revert InvalidProposalState();
        if (block.number <= p.votingEndBlock) revert InvalidWindow();

        results = tallies[proposalId];
        int256 maxScore = type(int256).min;
        for (uint256 i; i < results.length; ++i) {
            uint256 abs = uint256(results[i] >= 0 ? results[i] : -results[i]);
            totalParticipation += abs;
            if (results[i] > maxScore) {
                maxScore = results[i];
                winningOption = i;
            }
        }
        quorumMet = totalParticipation >= params.values(ParameterRegistry.ParamKey.QUORUM_THRESHOLD);
        p.quorumMet = quorumMet;
        p.winningOption = winningOption;
        p.status = ProposalStatus.TALLIED;
        emit VotesTallied(proposalId, results, quorumMet, winningOption);
        _audit(
            keccak256("GATE_3_PROPOSAL"),
            keccak256("TALLY_VOTES"),
            proposalId,
            true,
            ILayer2AuditTrail.Severity.INFO,
            keccak256(abi.encodePacked(totalParticipation, quorumMet, winningOption))
        );
    }

    function executeProposal(bytes32 proposalId) external notSafeMode returns (bool success, bytes memory executionResult) {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.TALLIED) revert InvalidProposalState();
        if (!p.quorumMet || p.winningOption != 0) {
            p.status = ProposalStatus.REJECTED;
            _releaseLockedCredits(proposalId);
            _audit(
                keccak256("GATE_3_PROPOSAL"),
                keccak256("EXECUTE_PROPOSAL"),
                proposalId,
                false,
                ILayer2AuditTrail.Severity.WARN,
                keccak256(abi.encodePacked(uint256(p.status), p.quorumMet, p.winningOption))
            );
            return (false, "");
        }
        (success, executionResult) = p.target.call(p.executionPayload);
        if (success) {
            p.status = ProposalStatus.EXECUTED;
            emit ProposalExecuted(proposalId, executionResult, block.timestamp);
            _audit(
                keccak256("GATE_3_PROPOSAL"),
                keccak256("EXECUTE_PROPOSAL"),
                proposalId,
                true,
                ILayer2AuditTrail.Severity.INFO,
                keccak256(executionResult)
            );
        } else {
            p.status = ProposalStatus.EXECUTION_FAILED;
            _releaseLockedCredits(proposalId);
            _audit(
                keccak256("GATE_3_PROPOSAL"),
                keccak256("EXECUTE_PROPOSAL"),
                proposalId,
                false,
                ILayer2AuditTrail.Severity.HIGH,
                keccak256(executionResult)
            );
        }
    }

    function triggerEmergencyStop(bytes32 reasonHash) external onlyOwner {
        safeMode = true;
        params.triggerEmergencyRevert();
        emit EmergencyStopTriggered(reasonHash, block.timestamp);
        _audit(
            keccak256("GATE_6_EMERGENCY"),
            keccak256("TRIGGER_EMERGENCY_STOP"),
            reasonHash,
            true,
            ILayer2AuditTrail.Severity.CRITICAL,
            keccak256(abi.encodePacked(block.number, block.timestamp))
        );
    }

    function liftEmergencyStop(bytes32 resolutionHash) external onlyOwner {
        safeMode = false;
        emit EmergencyStopLifted(resolutionHash, block.timestamp);
        _audit(
            keccak256("GATE_6_EMERGENCY"),
            keccak256("LIFT_EMERGENCY_STOP"),
            resolutionHash,
            true,
            ILayer2AuditTrail.Severity.HIGH,
            keccak256(abi.encodePacked(block.number, block.timestamp))
        );
    }

    function _releaseLockedCredits(bytes32 proposalId) internal {
        address[] storage list = voters[proposalId];
        for (uint256 i; i < list.length; ++i) {
            ledger.releaseCredits(list[i], proposalId);
        }
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
