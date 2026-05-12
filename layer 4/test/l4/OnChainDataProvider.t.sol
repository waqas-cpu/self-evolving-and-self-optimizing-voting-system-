// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OnChainDataProvider} from "../../contracts/l4/OnChainDataProvider.sol";
import {IOnChainData} from "../../contracts/l4/interfaces/IOnChainData.sol";
import {MockGovernanceViews, MockTreasuryViews, MockTokenPriceViews} from "./MockGovernance.sol";

contract OnChainDataProviderTest {
    function testComposesViews() public {
        MockGovernanceViews g = new MockGovernanceViews();
        MockTreasuryViews t = new MockTreasuryViews();
        MockTokenPriceViews p = new MockTokenPriceViews();
        g.setTurnout(1, 6500);
        g.setCredits(1, 1_000_000 ether);
        t.setFlows(1, 50 ether, 120 ether);
        p.setPrice(3_500e8);

        OnChainDataProvider provider = new OnChainDataProvider(address(g), address(t), address(p));
        IOnChainData.OnChainMetrics memory m = provider.getMetrics(1);
        require(m.voterTurnoutBps == 6500, "turnout");
        require(m.totalVoiceCreditsUsed == 1_000_000 ether, "credits");
        require(m.treasuryInflow == 50 ether && m.treasuryOutflow == 120 ether, "treasury");
        require(m.tokenPriceUsd == 3_500e8, "price");
    }
}
