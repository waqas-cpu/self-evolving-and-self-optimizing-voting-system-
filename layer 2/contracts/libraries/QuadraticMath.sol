// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library QuadraticMath {
    error LengthMismatch();

    function calculateQuadraticCost(uint256[] memory voteDistribution)
        internal
        pure
        returns (uint256 totalCost, uint256[] memory perOption)
    {
        uint256 len = voteDistribution.length;
        perOption = new uint256[](len);
        for (uint256 i; i < len; ++i) {
            uint256 v = voteDistribution[i];
            uint256 c = v * v;
            perOption[i] = c;
            totalCost += c;
        }
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y == 0) return 0;
        if (y <= 3) return 1;
        z = y;
        uint256 x = y / 2 + 1;
        while (x < z) {
            z = x;
            x = (y / x + x) / 2;
        }
    }

    function computeSignedPowers(uint256[] memory alloc, int8[] memory signs) internal pure returns (int256[] memory powers) {
        if (alloc.length != signs.length) revert LengthMismatch();
        powers = new int256[](alloc.length);
        for (uint256 i; i < alloc.length; ++i) {
            int256 root = int256(sqrt(alloc[i]));
            powers[i] = signs[i] < 0 ? -root : root;
        }
    }
}
