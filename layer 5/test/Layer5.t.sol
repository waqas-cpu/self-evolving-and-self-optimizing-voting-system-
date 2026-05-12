// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ParameterSet, Layer5State} from "../contracts/layer5/Layer5Types.sol";
import {FailsafeLogger} from "../contracts/layer5/FailsafeLogger.sol";
import {BaselineRegistry} from "../contracts/layer5/BaselineRegistry.sol";
import {TimelockController} from "../contracts/layer5/TimelockController.sol";
import {VetoAuthority} from "../contracts/layer5/VetoAuthority.sol";
import {MockRevertingL2} from "./mocks/MockRevertingL2.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockLayer2Registry} from "./mocks/MockLayer2Registry.sol";

/// @dev Layer 5 is purely subtractive: it delays, vetoes, or reverts — it does not mint or execute arbitrary external work.
contract Layer5Test is Test {
    uint256 internal constant MIN_DELAY = 100;

    address internal deployer = address(this);
    address internal intelligence = address(0xA11CE);

    MockLayer2Registry internal l2;
    FailsafeLogger internal logger;
    BaselineRegistry internal baseline;
    TimelockController internal timelock;
    VetoAuthority internal veto;

    address[7] internal stewards;

    function setUp() public {
        for (uint256 i = 0; i < 7; i++) {
            stewards[i] = address(uint160(0x1000 + i));
        }

        ParameterSet memory initialL2 = ParameterSet({
            votingDuration: 1_000,
            quorumThreshold: 1_000,
            creditRegenRate: 10,
            maxCreditCap: 10_000,
            submissionDelay: 50,
            proposalThreshold: 100
        });

        l2 = new MockLayer2Registry(initialL2);
        logger = new FailsafeLogger(deployer);

        baseline = new BaselineRegistry(initialL2, address(l2), address(logger), deployer);
        timelock = new TimelockController(MIN_DELAY, intelligence, address(l2), address(logger), deployer);

        veto = new VetoAuthority(
            _toDyn(stewards),
            5,
            address(timelock),
            address(baseline),
            address(logger),
            address(0),
            address(0),
            deployer
        );

        baseline.setPeers(address(timelock), address(veto));
        timelock.setWiring(address(baseline), address(veto));

        logger.authorizeModule(address(timelock));
        logger.authorizeModule(address(veto));
        logger.authorizeModule(address(baseline));
    }

    function _toDyn(address[7] memory a) private pure returns (address[] memory o) {
        o = new address[](7);
        for (uint256 i = 0; i < 7; i++) {
            o[i] = a[i];
        }
    }

    function _params() private pure returns (ParameterSet memory p) {
        p = ParameterSet({
            votingDuration: 2_000,
            quorumThreshold: 2_000,
            creditRegenRate: 20,
            maxCreditCap: 20_000,
            submissionDelay: 100,
            proposalThreshold: 200
        });
    }

    function test_CannotExecuteBeforeDelay() public {
        vm.prank(intelligence);
        bytes32 id = timelock.queueAdjustment(_params());

        vm.expectRevert(TimelockController.TooEarly.selector);
        timelock.executeAdjustment(id);
    }

    function test_VetoRestoresBaseline() public {
        vm.prank(intelligence);
        bytes32 id = timelock.queueAdjustment(_params());

        string memory j =
            "This veto justification is long enough to meet the twenty character minimum requirement.";

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(stewards[i]);
            veto.castVeto(id, j);
        }

        assertEq(uint256(baseline.getCurrentHash()), uint256(baseline.getBaselineHash()));
        assertTrue(l2.safeMode());
    }

    function test_VetoCannotInitiateQueue() public {
        vm.expectRevert(TimelockController.NotIntelligenceLayer.selector);
        vm.prank(address(veto));
        timelock.queueAdjustment(_params());
    }

    function test_RagequitOnlyDuringCrisis() public {
        ParameterSet memory initialL2 = ParameterSet({
            votingDuration: 1_000,
            quorumThreshold: 1_000,
            creditRegenRate: 10,
            maxCreditCap: 10_000,
            submissionDelay: 50,
            proposalThreshold: 100
        });
        MockLayer2Registry l2local = new MockLayer2Registry(initialL2);
        FailsafeLogger loglocal = new FailsafeLogger(deployer);
        BaselineRegistry blocal = new BaselineRegistry(initialL2, address(l2local), address(loglocal), deployer);
        TimelockController tlocal =
            new TimelockController(MIN_DELAY, intelligence, address(l2local), address(loglocal), deployer);

        MockERC20 treasury = new MockERC20();
        MockERC20 voice = new MockERC20();

        VetoAuthority vlocal = new VetoAuthority(
            _toDyn(stewards),
            5,
            address(tlocal),
            address(blocal),
            address(loglocal),
            address(treasury),
            address(voice),
            deployer
        );

        blocal.setPeers(address(tlocal), address(vlocal));
        tlocal.setWiring(address(blocal), address(vlocal));
        loglocal.authorizeModule(address(tlocal));
        loglocal.authorizeModule(address(vlocal));
        loglocal.authorizeModule(address(blocal));

        vm.expectRevert(VetoAuthority.CrisisNotActive.selector);
        vlocal.ragequit();
    }

    function test_BaselineHashImmutable() public {
        bytes32 h0 = baseline.getBaselineHash();
        vm.prank(intelligence);
        bytes32 id = timelock.queueAdjustment(_params());

        string memory j =
            "This veto justification is long enough to meet the twenty character minimum requirement.";

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(stewards[i]);
            veto.castVeto(id, j);
        }

        assertEq(baseline.getBaselineHash(), h0);
        assertEq(baseline.getCurrentHash(), h0);
    }

    function test_NoSilentStateChanges_queueEmits() public {
        vm.recordLogs();
        vm.prank(intelligence);
        timelock.queueAdjustment(_params());
        assertGt(vm.getRecordedLogs().length, 0);
    }

    function test_JustificationRequired() public {
        vm.prank(intelligence);
        bytes32 id = timelock.queueAdjustment(_params());

        vm.expectRevert(VetoAuthority.JustificationTooShort.selector);
        vm.prank(stewards[0]);
        veto.castVeto(id, "too short");
    }

    function test_Layer3CannotBypassTimelock_NonIntelligenceCannotQueue() public {
        vm.expectRevert(TimelockController.NotIntelligenceLayer.selector);
        timelock.queueAdjustment(_params());
    }

    function test_ApplyFailureRestoresBaseline() public {
        MockRevertingL2 bad = new MockRevertingL2();
        FailsafeLogger loglocal = new FailsafeLogger(deployer);
        TimelockController tl =
            new TimelockController(MIN_DELAY, intelligence, address(bad), address(loglocal), deployer);

        ParameterSet memory bp = ParameterSet({
            votingDuration: 1_000,
            quorumThreshold: 1_000,
            creditRegenRate: 10,
            maxCreditCap: 10_000,
            submissionDelay: 50,
            proposalThreshold: 100
        });
        BaselineRegistry bl = new BaselineRegistry(bp, address(bad), address(loglocal), deployer);

        VetoAuthority v2 = new VetoAuthority(
            _toDyn(stewards),
            5,
            address(tl),
            address(bl),
            address(loglocal),
            address(0),
            address(0),
            deployer
        );

        bl.setPeers(address(tl), address(v2));
        tl.setWiring(address(bl), address(v2));
        loglocal.authorizeModule(address(tl));
        loglocal.authorizeModule(address(bl));

        vm.prank(intelligence);
        bytes32 id = tl.queueAdjustment(_params());

        vm.warp(block.timestamp + MIN_DELAY + 1);
        tl.executeAdjustment(id);

        assertEq(uint256(tl.adjustmentState(id)), uint256(Layer5State.VETOED));
        assertEq(uint256(bl.getCurrentHash()), uint256(bl.getBaselineHash()));
    }
}
