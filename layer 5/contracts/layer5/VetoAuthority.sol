// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "../utils/Ownable.sol";
import {Layer5State} from "./Layer5Types.sol";
import {ITimelockController} from "./interfaces/ITimelockController.sol";
import {IBaselineRegistry} from "./interfaces/IBaselineRegistry.sol";
import {IFailsafeLogger} from "./interfaces/IFailsafeLogger.sol";
import {IERC20Minimal} from "./interfaces/IERC20Minimal.sol";

/// @title VetoAuthority
/// @notice Multisig veto council: subtractive-only; atomic cancel + baseline restore; optional ragequit during crisis (V1–V5, V4).
contract VetoAuthority is Ownable {
    uint256 public constant CRISIS_WINDOW = 7 days;
    uint256 public constant MIN_JUSTIFICATION_LEN = 20;
    uint256 public constant RAGEQUIT_MIN_VETOES = 3;

    ITimelockController public immutable timelock;
    IBaselineRegistry public immutable baseline;
    IFailsafeLogger public immutable logger;

    IERC20Minimal public immutable treasuryToken;
    IERC20Minimal public immutable voiceToken;

    address[] private _stewards;
    mapping(address => bool) public isSteward;
    mapping(address => uint256) public stewardIndexPlusOne;

    uint256 public immutable threshold;
    uint256 public immutable stewardCount;

    mapping(bytes32 => mapping(address => bool)) public hasVetoed;
    mapping(bytes32 => uint256) public vetoVoteCount;

    uint256[] private _vetoExecutionTimes;

    error InvalidCouncil();
    error NotSteward();
    error AlreadyVetoedBySteward();
    error JustificationTooShort();
    error RagequitUnavailable();
    error NoVoiceCredits();
    error CrisisNotActive();
    error TransferFailed();
    error AdjustmentNotQueued();

    event VetoCast(bytes32 indexed adjustmentId, address indexed steward, uint256 voteCount);
    event VetoFinalized(bytes32 indexed adjustmentId, address indexed tippingSteward);
    event Ragequit(address indexed account, uint256 voiceBurned, uint256 payout);

    constructor(
        address[] memory stewards_,
        uint256 threshold_,
        address timelock_,
        address baseline_,
        address logger_,
        address treasuryToken_,
        address voiceToken_,
        address initialOwner
    ) Ownable(initialOwner) {
        if (stewards_.length < 7) revert InvalidCouncil();
        if (threshold_ * 100 < stewards_.length * 60) revert InvalidCouncil();

        timelock = ITimelockController(timelock_);
        baseline = IBaselineRegistry(baseline_);
        logger = IFailsafeLogger(logger_);
        treasuryToken = IERC20Minimal(treasuryToken_);
        voiceToken = IERC20Minimal(voiceToken_);

        threshold = threshold_;
        stewardCount = stewards_.length;

        _stewards = stewards_;
        for (uint256 i = 0; i < stewards_.length; i++) {
            address s = stewards_[i];
            if (s == address(0)) revert InvalidCouncil();
            if (isSteward[s]) revert InvalidCouncil();
            isSteward[s] = true;
            stewardIndexPlusOne[s] = i + 1;
        }
    }

    function stewards() external view returns (address[] memory) {
        return _stewards;
    }

    modifier onlySteward() {
        if (!isSteward[msg.sender]) revert NotSteward();
        _;
    }

    modifier onlyDuringCrisis() {
        if (!_isCrisisActive()) revert CrisisNotActive();
        _;
    }

    function castVeto(bytes32 adjustmentId, string calldata justification) external onlySteward {
        if (timelock.adjustmentState(adjustmentId) != uint8(Layer5State.QUEUED)) {
            revert AdjustmentNotQueued();
        }
        if (bytes(justification).length < MIN_JUSTIFICATION_LEN) revert JustificationTooShort();
        if (hasVetoed[adjustmentId][msg.sender]) revert AlreadyVetoedBySteward();

        hasVetoed[adjustmentId][msg.sender] = true;
        uint256 vc = ++vetoVoteCount[adjustmentId];

        emit VetoCast(adjustmentId, msg.sender, vc);
        logger.appendChainLog(20, abi.encode(adjustmentId, msg.sender, vc, justification));

        if (vc >= threshold) {
            timelock.cancelAdjustment(adjustmentId, msg.sender, justification);
            baseline.restoreToBaseline();
            _recordVetoExecution();
            emit VetoFinalized(adjustmentId, msg.sender);
            logger.appendChainLog(21, abi.encode(adjustmentId, msg.sender));
        }
    }

    /// @notice Economic exit hatch only after >=3 full veto executions within 7 days (V4). Transfers are best-effort;
    ///         treasury must be funded on this contract. No Layer 5 module other than ragequit moves treasury (horizontal note 5).
    function ragequit() external onlyDuringCrisis {
        if (address(treasuryToken) == address(0) || address(voiceToken) == address(0)) {
            revert RagequitUnavailable();
        }

        uint256 bal = voiceToken.balanceOf(msg.sender);
        if (bal == 0) revert NoVoiceCredits();

        uint256 supply = voiceToken.totalSupply();
        if (supply == 0) revert RagequitUnavailable();

        uint256 treasuryBal = treasuryToken.balanceOf(address(this));
        uint256 payout = (treasuryBal * bal) / supply;

        if (!voiceToken.transferFrom(msg.sender, address(this), bal)) revert TransferFailed();
        if (payout > 0 && !treasuryToken.transfer(msg.sender, payout)) revert TransferFailed();

        emit Ragequit(msg.sender, bal, payout);
        logger.appendChainLog(22, abi.encode(msg.sender, bal, payout));
    }

    function recentVetoExecutionCount() external view returns (uint256) {
        return _pruneAndCount(block.timestamp);
    }

    function _recordVetoExecution() internal {
        _vetoExecutionTimes.push(block.timestamp);
    }

    function _isCrisisActive() internal view returns (bool) {
        return _pruneAndCount(block.timestamp) >= RAGEQUIT_MIN_VETOES;
    }

    function _pruneAndCount(uint256 nowTs) internal view returns (uint256 count) {
        uint256 cutoff = nowTs > CRISIS_WINDOW ? nowTs - CRISIS_WINDOW : 0;
        count = 0;
        for (uint256 i = 0; i < _vetoExecutionTimes.length; i++) {
            if (_vetoExecutionTimes[i] >= cutoff) {
                count++;
            }
        }
    }
}
