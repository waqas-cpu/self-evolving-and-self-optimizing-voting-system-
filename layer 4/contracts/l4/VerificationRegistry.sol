// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";
import {IVerificationRegistry} from "./interfaces/IVerificationRegistry.sol";

/// @notice Gates L4-01, L4-03, L4-07 — stake-weighted registry with faults and slashing hooks.
contract VerificationRegistry is Ownable, IVerificationRegistry {
    uint256 public constant STAKE_MIN = 10_000 ether;
    uint256 public constant SLASH_BPS = 5000;

    mapping(address => uint256) public override stakeOf;
    mapping(address => bool) public approved;
    mapping(address => uint256) public override faultCount;
    address[] internal _oracles;
    mapping(address => uint256) internal _indexPlus1;

    address public slashAuthority;

    event OracleRegistered(address indexed oracle, uint256 stakeAfter);
    event OracleApproved(address indexed oracle, bool allowed);
    event StakeDeposited(address indexed oracle, uint256 amount);
    event StakeWithdrawn(address indexed oracle, uint256 amount);
    event FaultRecorded(address indexed oracle, uint256 newFaults);
    event Slashed(address indexed oracle, uint256 amount, address indexed authority);

    error InsufficientStake();
    error UnknownOracle();
    error TransferFailed();
    error Unauthorized();

    constructor(address initialOwner, address slashAuthority_) Ownable(initialOwner) {
        slashAuthority = slashAuthority_ == address(0) ? initialOwner : slashAuthority_;
    }

    function setApproved(address oracle, bool allowed) external onlyOwner {
        approved[oracle] = allowed;
        emit OracleApproved(oracle, allowed);
    }

    function setSlashAuthority(address a) external onlyOwner {
        slashAuthority = a;
    }

    function activeOracleCount() external view override returns (uint256) {
        return _oracles.length;
    }

    function activeOracleAt(uint256 index) external view override returns (address) {
        return _oracles[index];
    }

    function isApproved(address oracle) external view override returns (bool) {
        return approved[oracle];
    }

    /// @notice Payable stake deposit; registers oracle in the active set on first funding.
    function depositStake() external payable {
        if (msg.value == 0) return;
        stakeOf[msg.sender] += msg.value;
        if (stakeOf[msg.sender] < STAKE_MIN) revert InsufficientStake();
        if (_indexPlus1[msg.sender] == 0) {
            _oracles.push(msg.sender);
            _indexPlus1[msg.sender] = _oracles.length;
        }
        emit StakeDeposited(msg.sender, msg.value);
        emit OracleRegistered(msg.sender, stakeOf[msg.sender]);
    }

    function withdrawStake(uint256 amount) external {
        if (amount == 0) return;
        if (stakeOf[msg.sender] < amount) revert InsufficientStake();
        stakeOf[msg.sender] -= amount;
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit StakeWithdrawn(msg.sender, amount);
    }

    /// @notice Gate L4-01 failure accounting — increments faults for bad attestations.
    function recordFault(address oracle) external onlyOwner {
        faultCount[oracle] += 1;
        emit FaultRecorded(oracle, faultCount[oracle]);
    }

    /// @notice Gate L4-07 — slash a portion of stake; intended to be gated by Layer 5 multisig in production.
    function slash(address oracle, uint256 bps) external {
        if (msg.sender != slashAuthority && msg.sender != owner) revert Unauthorized();
        if (_indexPlus1[oracle] == 0) revert UnknownOracle();
        uint256 s = stakeOf[oracle];
        uint256 penalty = (s * bps) / 10_000;
        stakeOf[oracle] = s - penalty;
        emit Slashed(oracle, penalty, msg.sender);
    }

    function slashDefault(address oracle) external {
        if (msg.sender != slashAuthority && msg.sender != owner) revert Unauthorized();
        uint256 s = stakeOf[oracle];
        uint256 penalty = (s * SLASH_BPS) / 10_000;
        stakeOf[oracle] = s - penalty;
        emit Slashed(oracle, penalty, msg.sender);
    }

    receive() external payable {}
}
