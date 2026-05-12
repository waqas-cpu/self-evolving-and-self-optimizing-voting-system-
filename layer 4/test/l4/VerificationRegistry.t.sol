// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VerificationRegistry} from "../../contracts/l4/VerificationRegistry.sol";

interface Vm {
    function deal(address who, uint256 amt) external;
}

contract VerificationRegistryTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function testStakeAndSlash() public {
        vm.deal(address(this), 200_000 ether);
        VerificationRegistry reg = new VerificationRegistry(address(this), address(this));
        reg.depositStake{value: 11_000 ether}();
        require(reg.stakeOf(address(this)) >= 10_000 ether, "staked");

        reg.slash(address(this), 5000);
        require(reg.stakeOf(address(this)) < 11_000 ether, "slashed");
    }
}
