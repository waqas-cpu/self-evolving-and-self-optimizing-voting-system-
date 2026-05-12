// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";
import {IDataBuffer} from "./interfaces/IDataBuffer.sol";

/// @notice Module 4F — commit Merkle root, 1-hour reveal delay, 24-hour consume window after reveal.
contract DataBuffer is Ownable, IDataBuffer {
    uint256 public constant REVEAL_DELAY = 1 hours;
    uint256 public constant CONSUME_WINDOW = 24 hours;
    uint256 public constant MAX_LEAVES = 100;

    struct Batch {
        bytes32 merkleRoot;
        uint256 committedAt;
        uint256 revealAt;
        uint256 consumeDeadline;
        uint256 leafCount;
        bool revealed;
        bool consumed;
    }

    address public consumer;

    mapping(bytes32 => Batch) internal _batches;

    event DataCommitted(bytes32 indexed batchId, bytes32 merkleRoot, uint256 revealTime, uint256 leafCount);
    event DataRevealed(bytes32 indexed batchId);
    event DataConsumed(bytes32 indexed batchId);
    event ConsumerUpdated(address indexed consumer);

    error UnknownBatch();
    error BatchAlreadyExists();
    error TooManyLeaves();
    error NotYetRevealable();
    error AlreadyRevealed();
    error NotRevealed();
    error AlreadyConsumed();
    error Expired();
    error UnauthorizedConsumer();

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setConsumer(address c) external onlyOwner {
        consumer = c;
        emit ConsumerUpdated(c);
    }

    function commit(bytes32 batchId, bytes32 merkleRoot, uint256 leafCount) external onlyOwner {
        if (_batches[batchId].committedAt != 0) revert BatchAlreadyExists();
        if (leafCount == 0 || leafCount > MAX_LEAVES) revert TooManyLeaves();
        uint256 revealAt = block.timestamp + REVEAL_DELAY;
        _batches[batchId] = Batch({
            merkleRoot: merkleRoot,
            committedAt: block.timestamp,
            revealAt: revealAt,
            consumeDeadline: 0,
            leafCount: leafCount,
            revealed: false,
            consumed: false
        });
        emit DataCommitted(batchId, merkleRoot, revealAt, leafCount);
    }

    function reveal(bytes32 batchId) external {
        Batch storage b = _batches[batchId];
        if (b.committedAt == 0) revert UnknownBatch();
        if (b.revealed) revert AlreadyRevealed();
        if (block.timestamp < b.revealAt) revert NotYetRevealable();
        b.revealed = true;
        b.consumeDeadline = block.timestamp + CONSUME_WINDOW;
        emit DataRevealed(batchId);
    }

    function consume(bytes32 batchId) external override {
        if (consumer != address(0) && msg.sender != consumer && msg.sender != owner) {
            revert UnauthorizedConsumer();
        }
        Batch storage b = _batches[batchId];
        if (b.committedAt == 0) revert UnknownBatch();
        if (!b.revealed) revert NotRevealed();
        if (b.consumed) revert AlreadyConsumed();
        if (block.timestamp > b.consumeDeadline) revert Expired();
        b.consumed = true;
        emit DataConsumed(batchId);
    }

    function getMerkleRoot(bytes32 batchId) external view override returns (bytes32) {
        return _batches[batchId].merkleRoot;
    }

    function isRevealed(bytes32 batchId) external view override returns (bool) {
        return _batches[batchId].revealed;
    }

    function isConsumed(bytes32 batchId) external view override returns (bool) {
        return _batches[batchId].consumed;
    }

    function getBatch(bytes32 batchId)
        external
        view
        returns (
            bytes32 merkleRoot,
            uint256 committedAt,
            uint256 revealAt,
            uint256 consumeDeadline,
            uint256 leafCount,
            bool revealed,
            bool consumed
        )
    {
        Batch storage b = _batches[batchId];
        return (b.merkleRoot, b.committedAt, b.revealAt, b.consumeDeadline, b.leafCount, b.revealed, b.consumed);
    }
}
