// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOnChainData} from "./interfaces/IOnChainData.sol";
import {IGovernanceViews, ITreasuryViews, ITokenPriceViews} from "./interfaces/IGovernanceViews.sol";

/// @notice Module 4A — read-only composition of governance / treasury / price views at a pinned block context.
contract OnChainDataProvider is IOnChainData {
    IGovernanceViews public immutable governance;
    ITreasuryViews public immutable treasury;
    ITokenPriceViews public immutable tokenPrice;

    constructor(address governance_, address treasury_, address tokenPrice_) {
        governance = IGovernanceViews(governance_);
        treasury = ITreasuryViews(treasury_);
        tokenPrice = ITokenPriceViews(tokenPrice_);
    }

    function getMetrics(uint256 proposalId) external view returns (OnChainMetrics memory m) {
        m.proposalId = proposalId;
        m.timestamp = block.timestamp;
        m.blockHash = blockhash(block.number - 1);

        if (address(governance) != address(0)) {
            m.voterTurnoutBps = governance.voterTurnoutBps(proposalId);
            m.totalVoiceCreditsUsed = governance.totalVoiceCreditsUsed(proposalId);
        }
        if (address(treasury) != address(0)) {
            (m.treasuryInflow, m.treasuryOutflow) = treasury.flowsForProposal(proposalId);
        }
        if (address(tokenPrice) != address(0)) {
            m.tokenPriceUsd = tokenPrice.latestPriceUsd8();
        }
    }
}
