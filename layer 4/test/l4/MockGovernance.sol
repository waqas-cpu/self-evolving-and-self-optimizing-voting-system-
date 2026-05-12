// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGovernanceViews, ITreasuryViews, ITokenPriceViews} from "../../contracts/l4/interfaces/IGovernanceViews.sol";

contract MockGovernanceViews is IGovernanceViews {
    mapping(uint256 => uint256) internal _turnout;
    mapping(uint256 => uint256) internal _credits;

    function setTurnout(uint256 proposalId, uint256 bps) external {
        _turnout[proposalId] = bps;
    }

    function setCredits(uint256 proposalId, uint256 c) external {
        _credits[proposalId] = c;
    }

    function voterTurnoutBps(uint256 proposalId) external view override returns (uint256) {
        return _turnout[proposalId];
    }

    function totalVoiceCreditsUsed(uint256 proposalId) external view override returns (uint256) {
        return _credits[proposalId];
    }
}

contract MockTreasuryViews is ITreasuryViews {
    mapping(uint256 => uint256) internal _in;
    mapping(uint256 => uint256) internal _out;

    function setFlows(uint256 proposalId, uint256 inf, uint256 o) external {
        _in[proposalId] = inf;
        _out[proposalId] = o;
    }

    function flowsForProposal(uint256 proposalId)
        external
        view
        override
        returns (uint256 inflow, uint256 outflow)
    {
        return (_in[proposalId], _out[proposalId]);
    }
}

contract MockTokenPriceViews is ITokenPriceViews {
    uint256 public price = 2_000e8;

    function setPrice(uint256 p) external {
        price = p;
    }

    function latestPriceUsd8() external view override returns (uint256) {
        return price;
    }
}
