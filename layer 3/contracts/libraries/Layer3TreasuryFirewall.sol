// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILayer2ParameterRegistry} from "../interfaces/ILayer2ParameterRegistry.sol";
import {ILayer5Timelock} from "../interfaces/ILayer5Timelock.sol";

/// @notice GATE 5 — outbound calls are whitelisted: either legacy L2 proposals or Layer 5 timelock queue only, zero value.
library Layer3TreasuryFirewall {
    error Gate5NonZeroValue();
    error Gate5TargetNotRegistry();
    error Gate5TargetNotTimelock();
    error Gate5ForbiddenSelector();

    /// @dev When `timelock` is set, only `timelock.queueAdjustment` is allowed (Layer 5 failsafe path).
    ///      When `timelock` is zero, only `registry.proposeParameterAdjustment` is allowed (legacy tests / rollout).
    function verifyParameterBroadcast(
        address registry,
        address timelock,
        address to,
        uint256 callValue,
        bytes4 selector
    ) internal pure {
        if (callValue != 0) revert Gate5NonZeroValue();
        if (timelock != address(0)) {
            if (to != timelock) revert Gate5TargetNotTimelock();
            if (selector != ILayer5Timelock.queueAdjustment.selector) revert Gate5ForbiddenSelector();
        } else {
            if (to != registry) revert Gate5TargetNotRegistry();
            if (selector != ILayer2ParameterRegistry.proposeParameterAdjustment.selector) {
                revert Gate5ForbiddenSelector();
            }
        }
    }

    /// @dev Backward-compatible alias for legacy-only configurations.
    function verifyRegistryProposal(address registry, address to, uint256 callValue, bytes4 selector)
        internal
        pure
    {
        verifyParameterBroadcast(registry, address(0), to, callValue, selector);
    }
}
