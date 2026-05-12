// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "../utils/Ownable.sol";
import {ParameterSet} from "./Layer5Types.sol";
import {IBaselineRegistry} from "./interfaces/IBaselineRegistry.sol";
import {ILayer2ParameterRegistryL5} from "./interfaces/ILayer2ParameterRegistryL5.sol";
import {IFailsafeLogger} from "./interfaces/IFailsafeLogger.sol";

/// @title BaselineRegistry
/// @notice Immutable baseline snapshot; atomic restore to Layer 2; current config hash tracking (B1–B5).
contract BaselineRegistry is IBaselineRegistry, Ownable {
    /// @dev Constructor-set snapshot; no mutator — frozen after deploy (B1).
    ParameterSet private _baseline;
    bytes32 public immutable immutableBaselineHash;

    bytes32 public currentConfigHash;

    ILayer2ParameterRegistryL5 public immutable l2;
    IFailsafeLogger public immutable logger;

    address public timelock;
    address public vetoAuthority;

    error PeersAlreadySet();
    error UnauthorizedRestorer();

    event PeersWired(address indexed timelock, address indexed vetoAuthority);

    constructor(
        ParameterSet memory baseline_,
        address l2_,
        address logger_,
        address initialOwner
    ) Ownable(initialOwner) {
        _baseline = baseline_;
        immutableBaselineHash = keccak256(abi.encode(baseline_));
        currentConfigHash = immutableBaselineHash;
        l2 = ILayer2ParameterRegistryL5(l2_);
        logger = IFailsafeLogger(logger_);
    }

    /// @dev One-time wiring after Timelock + Veto are deployed (avoid circular CREATE dependencies).
    function setPeers(address timelock_, address vetoAuthority_) external onlyOwner {
        if (timelock != address(0)) revert PeersAlreadySet();
        timelock = timelock_;
        vetoAuthority = vetoAuthority_;
        emit PeersWired(timelock_, vetoAuthority_);
    }

    modifier onlyAuthorizedRestorer() {
        if (msg.sender != timelock && msg.sender != vetoAuthority) revert UnauthorizedRestorer();
        _;
    }

    function baselineParams() external view returns (ParameterSet memory) {
        return _baseline;
    }

    function getBaselineHash() external view returns (bytes32) {
        return immutableBaselineHash;
    }

    function getCurrentHash() external view returns (bytes32) {
        return currentConfigHash;
    }

    /// @notice Atomic baseline restoration on Layer 2 (B3, B4). Callable by Timelock (failed exec) or Veto.
    function restoreToBaseline() external onlyAuthorizedRestorer {
        bytes32 beforeHash = currentConfigHash;
        l2.restoreBaselineFromLayer5();
        currentConfigHash = immutableBaselineHash;
        emit BaselineRestored(msg.sender, block.timestamp, immutableBaselineHash);
        logger.logStateDiff(bytes32(uint256(1)), beforeHash, currentConfigHash);
        logger.appendChainLog(3, abi.encode(msg.sender, block.timestamp));
    }

    /// @notice Timelock records successful execution hash (post-apply).
    function recordExecutedConfig(bytes32 newConfigHash) external override {
        if (msg.sender != timelock) revert UnauthorizedRestorer();
        bytes32 beforeHash = currentConfigHash;
        currentConfigHash = newConfigHash;
        emit CurrentConfigUpdated(newConfigHash);
        logger.logStateDiff(bytes32(uint256(2)), beforeHash, newConfigHash);
        logger.appendChainLog(4, abi.encode(newConfigHash));
    }
}
