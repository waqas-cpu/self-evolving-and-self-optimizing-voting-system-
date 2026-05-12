// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NodeSelectionLib} from "../../contracts/l4/NodeSelectionLib.sol";

contract NodeSelectionTest {
    function testSelectsThreeDistinct() public pure {
        address[] memory pool = new address[](5);
        pool[0] = address(0x1);
        pool[1] = address(0x2);
        pool[2] = address(0x3);
        pool[3] = address(0x4);
        pool[4] = address(0x5);
        address[] memory picked = NodeSelectionLib.selectNodes(pool, keccak256("seed"), 3);
        require(picked.length == 3, "len");
        require(picked[0] != picked[1] && picked[0] != picked[2] && picked[1] != picked[2], "distinct");
    }
}
