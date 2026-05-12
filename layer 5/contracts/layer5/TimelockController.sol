// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "../utils/Ownable.sol";
import {ParameterSet, Layer5State} from "./Layer5Types.sol";
import {ITimelockController} from "./interfaces/ITimelockController.sol";
import {IBaselineRegistry} from "./interfaces/IBaselineRegistry.sol";
import {ILayer2ParameterRegistryL5} from "./interfaces/ILayer2ParameterRegistryL5.sol";
import {IFailsafeLogger} from "./interfaces/IFailsafeLogger.sol";

/// @title TimelockController
/// @notice Mandatory delay for Layer 3–originated parameter sets; subtractive cancel via veto (T1–T5).
contract TimelockController is ITimelockController, Ownable {
    uint256 public immutable MIN_DELAY;
    address public immutable intelligenceLayer;

    ILayer2ParameterRegistryL5 public immutable l2;
    IFailsafeLogger public immutable logger;

    IBaselineRegistry public baselineRegistry;
    address public vetoAuthority;

    uint256 private _adjustmentNonce;

    struct Adjustment {
        ParameterSet params;
        uint256 executableAt;
        Layer5State state;
    }

    mapping(bytes32 => Adjustment) public adjustments;

    error WiringAlreadySet();
    error NotIntelligenceLayer();
    error NotVetoAuthority();
    error TooEarly();
    error NotQueued();
    error NotWired();
    error VetoNotSet();
    error VetoWindowClosed();

    modifier onlyIntelligenceLayer() {
        if (msg.sender != intelligenceLayer) revert NotIntelligenceLayer();
        _;
    }

    modifier onlyVetoAuthority() {
        if (vetoAuthority == address(0)) revert VetoNotSet();
        if (msg.sender != vetoAuthority) revert NotVetoAuthority();
        _;
    }

    constructor(
        uint256 minDelay_,
        address intelligenceLayer_,
        address l2_,
        address logger_,
        address initialOwner
    ) Ownable(initialOwner) {
        if (intelligenceLayer_ == address(0) || l2_ == address(0) || logger_ == address(0)) {
            revert ZeroAddress();
        }
        MIN_DELAY = minDelay_;
        intelligenceLayer = intelligenceLayer_;
        l2 = ILayer2ParameterRegistryL5(l2_);
        logger = IFailsafeLogger(logger_);
    }

    function setWiring(address baselineRegistry_, address vetoAuthority_) external onlyOwner {
        if (address(baselineRegistry) != address(0)) revert WiringAlreadySet();
        if (baselineRegistry_ == address(0) || vetoAuthority_ == address(0)) revert ZeroAddress();
        baselineRegistry = IBaselineRegistry(baselineRegistry_);
        vetoAuthority = vetoAuthority_;
    }

    function queueAdjustment(ParameterSet calldata params)
        external
        onlyIntelligenceLayer
        returns (bytes32 id)
    {
        if (address(baselineRegistry) == address(0)) revert NotWired();
        unchecked {
            _adjustmentNonce += 1;
        }
        id = keccak256(abi.encode(_adjustmentNonce, block.chainid, address(this), params));
        uint256 executableAt = block.timestamp + MIN_DELAY;
        adjustments[id] = Adjustment(params, executableAt, Layer5State.QUEUED);
        emit AdjustmentQueued(id, params, executableAt);
        logger.appendChainLog(10, abi.encode(id, executableAt));
    }

    /// @dev Anyone may execute after the delay (liveness). If Layer 2 apply fails, baseline is restored atomically (B2).
    function executeAdjustment(bytes32 id) external {
        if (address(baselineRegistry) == address(0)) revert NotWired();
        Adjustment storage a = adjustments[id];
        if (a.state != Layer5State.QUEUED) revert NotQueued();
        if (block.timestamp < a.executableAt) revert TooEarly();

        bytes32 beforeHash = baselineRegistry.getCurrentHash();
        try l2.applyLayer5ParameterSet(a.params) {
            bytes32 newHash = keccak256(abi.encode(a.params));
            baselineRegistry.recordExecutedConfig(newHash);
            a.state = Layer5State.ACTIVE;
            emit AdjustmentExecuted(id);
            logger.logStateDiff(id, beforeHash, newHash);
            logger.appendChainLog(11, abi.encode(id));
        } catch {
            baselineRegistry.restoreToBaseline();
            a.state = Layer5State.VETOED;
            emit AdjustmentVetoed(id, address(this), "apply_failed:layer2_revert");
            logger.storeVetoJustification(id, "apply_failed:layer2_revert");
            logger.appendChainLog(14, abi.encode(id));
        }
    }

    function cancelAdjustment(bytes32 id, address vetoActor, string calldata justification)
        external
        onlyVetoAuthority
    {
        Adjustment storage a = adjustments[id];
        if (a.state != Layer5State.QUEUED) revert NotQueued();
        if (block.timestamp >= a.executableAt) revert VetoWindowClosed();
        a.state = Layer5State.VETOED;
        emit AdjustmentVetoed(id, vetoActor, justification);
        logger.storeVetoJustification(id, justification);
        logger.appendChainLog(12, abi.encode(id, vetoActor, justification));
    }

    function adjustmentState(bytes32 id) external view returns (uint8 state) {
        return uint8(adjustments[id].state);
    }
}
