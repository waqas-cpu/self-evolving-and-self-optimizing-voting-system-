// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";

/// @notice GATE 7 — append-only training / feedback points keyed to finalized proposals and model versions.
contract Layer3FeedbackLedger is Ownable {
    struct TrainingDataPoint {
        bytes32 modelVersionId;
        uint256 proposalCount;
        uint256 predictionAccuracyWad;
        uint256 avgVoterTurnout;
        uint256 avgTimeToConsensus;
        uint256 timestamp;
        bool outlierFlagged;
        bytes32 finalizedProposalRoot;
    }

    TrainingDataPoint[] internal _points;
    mapping(address => bool) public writers;

    event WriterUpdated(address indexed writer, bool allowed);
    event FeedbackCaptured(
        uint256 indexed index, bytes32 indexed modelVersionId, bytes32 finalizedProposalRoot
    );

    error UnauthorizedWriter();

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setWriter(address writer, bool allowed) external onlyOwner {
        writers[writer] = allowed;
        emit WriterUpdated(writer, allowed);
    }

    function captureFeedback(TrainingDataPoint calldata p) external {
        if (!writers[msg.sender] && msg.sender != owner) revert UnauthorizedWriter();
        _points.push(p);
        emit FeedbackCaptured(_points.length - 1, p.modelVersionId, p.finalizedProposalRoot);
    }

    function pointCount() external view returns (uint256) {
        return _points.length;
    }

    function getPoint(uint256 index) external view returns (TrainingDataPoint memory) {
        return _points[index];
    }
}
