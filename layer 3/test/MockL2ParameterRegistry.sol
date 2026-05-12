// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILayer2ParameterRegistry} from "../contracts/interfaces/ILayer2ParameterRegistry.sol";

/// @notice Lightweight registry for Layer 3 tests — values chosen so WAD mapping lands near 0.51 quorum.
contract MockL2ParameterRegistry is ILayer2ParameterRegistry {
    mapping(ParamKey => uint256) internal _values;
    mapping(ParamKey => uint256) internal _minBound;
    mapping(ParamKey => uint256) internal _maxBound;

    uint256 public proposalCount;

    event MockProposed(ParamKey indexed key, uint256 newValue, bytes32 justificationHash);

    constructor() {
        _minBound[ParamKey.QUORUM_THRESHOLD] = 100;
        _maxBound[ParamKey.QUORUM_THRESHOLD] = 100_000;
        _values[ParamKey.QUORUM_THRESHOLD] = 51_000;

        _minBound[ParamKey.VOTING_DURATION] = 1000;
        _maxBound[ParamKey.VOTING_DURATION] = 50_000;
        _values[ParamKey.VOTING_DURATION] = 10_000;

        _minBound[ParamKey.CREDIT_REGEN_RATE] = 1;
        _maxBound[ParamKey.CREDIT_REGEN_RATE] = 100;
        _values[ParamKey.CREDIT_REGEN_RATE] = 10;

        _minBound[ParamKey.PROPOSAL_THRESHOLD] = 100;
        _maxBound[ParamKey.PROPOSAL_THRESHOLD] = 10_000;
        _values[ParamKey.PROPOSAL_THRESHOLD] = 1000;

        _minBound[ParamKey.MAX_CREDIT_CAP] = 1000;
        _maxBound[ParamKey.MAX_CREDIT_CAP] = 1_000_000;
        _values[ParamKey.MAX_CREDIT_CAP] = 10_000;

        _minBound[ParamKey.SUBMISSION_DELAY] = 10;
        _maxBound[ParamKey.SUBMISSION_DELAY] = 1000;
        _values[ParamKey.SUBMISSION_DELAY] = 50;
    }

    function bounds(ParamKey key) external view override returns (uint256 min, uint256 max) {
        return (_minBound[key], _maxBound[key]);
    }

    function values(ParamKey key) external view override returns (uint256) {
        return _values[key];
    }

    function proposeParameterAdjustment(
        ParamKey key,
        uint256 newValue,
        bytes calldata,
        bytes32 justificationHash
    ) external override returns (bytes32 adjustmentId, uint256 effectiveBlock) {
        _values[key] = newValue;
        proposalCount += 1;
        adjustmentId = keccak256(abi.encodePacked(key, newValue, justificationHash, proposalCount));
        effectiveBlock = block.number + 1;
        emit MockProposed(key, newValue, justificationHash);
    }
}
