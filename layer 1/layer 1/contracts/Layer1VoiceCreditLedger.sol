// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";

contract Layer1VoiceCreditLedger is Ownable {
    mapping(bytes32 => uint256) public balances;
    mapping(bytes32 => bool) public frozen;
    mapping(bytes32 => mapping(uint64 => bool)) public mintedByEpoch;

    event CreditsAllocated(bytes32 indexed commitment, uint256 amount, uint64 epochId);
    event CreditsFrozen(bytes32 indexed commitment);
    event VoteCostDeducted(bytes32 indexed commitment, bytes32 indexed proposalId, uint256 cost);

    error AlreadyMintedThisEpoch();
    error InsufficientCredits();
    error FrozenIdentity();

    constructor(address initialOwner) Ownable(initialOwner) {}

    function allocateCredits(bytes32 commitment, uint256 amount, uint64 epochId) external onlyOwner {
        if (mintedByEpoch[commitment][epochId]) revert AlreadyMintedThisEpoch();
        mintedByEpoch[commitment][epochId] = true;
        balances[commitment] += amount;
        emit CreditsAllocated(commitment, amount, epochId);
    }

    function freeze(bytes32 commitment) external onlyOwner {
        frozen[commitment] = true;
        balances[commitment] = 0;
        emit CreditsFrozen(commitment);
    }

    function deductQuadraticCost(bytes32 commitment, uint256[] calldata votes, bytes32 proposalId) external onlyOwner {
        if (frozen[commitment]) revert FrozenIdentity();

        uint256 cost;
        for (uint256 i; i < votes.length; ++i) {
            unchecked {
                cost += votes[i] * votes[i];
            }
        }
        if (cost > balances[commitment]) revert InsufficientCredits();
        balances[commitment] -= cost;
        emit VoteCostDeducted(commitment, proposalId, cost);
    }
}
