// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockTarget {
    uint256 public number;
    bool public fail;

    function setFail(bool v) external {
        fail = v;
    }

    function setNumber(uint256 n) external returns (uint256) {
        require(!fail, "forced-fail");
        number = n;
        return n;
    }
}
