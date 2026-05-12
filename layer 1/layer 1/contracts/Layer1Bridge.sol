// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";

contract Layer1Bridge is Ownable {
    enum EventType {
        CredentialMinted,
        CreditInvalidated,
        EpochRollover
    }

    uint256 public immutable maxMintsPerBlock;
    mapping(uint256 => uint256) public mintedCountByBlock;
    mapping(bytes32 => bool) public revokedCommitments;
    uint256 public activeIdentityCount;

    event BridgeEvent(EventType indexed eventType, bytes payload);
    event CredentialRevoked(bytes32 indexed commitment);

    error MintRateLimitExceeded();

    constructor(address initialOwner, uint256 _maxMintsPerBlock) Ownable(initialOwner) {
        maxMintsPerBlock = _maxMintsPerBlock;
    }

    function emitCredentialMinted(bytes calldata payload) external onlyOwner {
        uint256 currentBlock = block.number;
        uint256 count = mintedCountByBlock[currentBlock] + 1;
        if (count > maxMintsPerBlock) revert MintRateLimitExceeded();
        mintedCountByBlock[currentBlock] = count;
        emit BridgeEvent(EventType.CredentialMinted, payload);
    }

    function emitCreditInvalidated(bytes32 commitment, bytes calldata payload) external onlyOwner {
        revokedCommitments[commitment] = true;
        emit BridgeEvent(EventType.CreditInvalidated, payload);
        emit CredentialRevoked(commitment);
    }

    function emitEpochRollover(bytes calldata payload) external onlyOwner {
        emit BridgeEvent(EventType.EpochRollover, payload);
    }

    function setActiveIdentityCount(uint256 count) external onlyOwner {
        activeIdentityCount = count;
    }

    function isCommitmentRevoked(bytes32 commitment) external view returns (bool) {
        return revokedCommitments[commitment];
    }

    function getActiveIdentityCount() external view returns (uint256) {
        return activeIdentityCount;
    }
}
