// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Gate L4-03 — deterministic selection from a staked pool (VRF placeholder; seed must be committed off-chain).
library NodeSelectionLib {
    error InsufficientNodes();

    /// @dev Returns `count` distinct addresses from `pool` using iterative Fisher–Yates with `keccak256` RNG.
    function selectNodes(address[] memory pool, bytes32 seed, uint256 count)
        internal
        pure
        returns (address[] memory picked)
    {
        if (pool.length < count || count < 3) revert InsufficientNodes();
        picked = new address[](count);
        address[] memory buf = new address[](pool.length);
        for (uint256 i = 0; i < pool.length; i++) {
            buf[i] = pool[i];
        }
        uint256 n = pool.length;
        for (uint256 j = 0; j < count; j++) {
            uint256 rnd = uint256(keccak256(abi.encodePacked(seed, j, buf[j], n))) % n;
            picked[j] = buf[rnd];
            buf[rnd] = buf[n - 1];
            n--;
        }
    }
}
