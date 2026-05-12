// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";

/// @notice GATE 8 — hash-committed model versions with explicit activation (meta-governance placeholder: `onlyOwner`).
contract Layer3ModelRegistry is Ownable {
    struct Version {
        bytes32 artifactHash;
        bytes32 metadataHash;
        bytes32 governanceVoteHash;
        bool exists;
        bool active;
    }

    mapping(bytes32 => Version) internal _versions;
    bytes32 public activeVersionId;

    event ModelRegistered(
        bytes32 indexed versionId,
        bytes32 artifactHash,
        bytes32 metadataHash,
        bytes32 governanceVoteHash
    );
    event ModelActivated(bytes32 indexed versionId);
    event ModelRolledBack(bytes32 indexed previousVersionId, bytes32 indexed newActiveVersionId);

    error UnknownVersion();
    error HashMismatch();

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Registers an approved artifact hash (must match supplied artifact hash).
    function registerModelVersion(
        bytes32 versionId,
        bytes32 artifactHash,
        bytes32 committedHash,
        bytes32 metadataHash,
        bytes32 governanceVoteHash
    ) external onlyOwner {
        if (artifactHash != committedHash) revert HashMismatch();
        _versions[versionId] = Version({
            artifactHash: artifactHash,
            metadataHash: metadataHash,
            governanceVoteHash: governanceVoteHash,
            exists: true,
            active: false
        });
        emit ModelRegistered(versionId, artifactHash, metadataHash, governanceVoteHash);
    }

    function activateModel(bytes32 versionId) public onlyOwner {
        Version storage v = _versions[versionId];
        if (!v.exists) revert UnknownVersion();
        if (activeVersionId != bytes32(0)) {
            _versions[activeVersionId].active = false;
        }
        activeVersionId = versionId;
        v.active = true;
        emit ModelActivated(versionId);
    }

    function rollbackTo(bytes32 versionId) external onlyOwner {
        bytes32 prev = activeVersionId;
        activateModel(versionId);
        emit ModelRolledBack(prev, versionId);
    }

    function isActive(bytes32 versionId) external view returns (bool) {
        return activeVersionId == versionId && _versions[versionId].active;
    }

    function getVersion(bytes32 versionId) external view returns (Version memory) {
        return _versions[versionId];
    }
}
