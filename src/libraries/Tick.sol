// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { LiquidityMath } from "src/libraries/LiquidityMath.sol";
import { Math } from "src/libraries/Math.sol";

/// @title Tick Library
/// @notice Provides functions for managing tick-level state in an automated market maker (AMM)
library Tick {
    /// @notice Represents the state of a single tick
    /// @param initialized Whether the tick has been initialized
    /// @param liquidityGross Total liquidity at the tick
    /// @param liquidityNet Net liquidity change when the tick is crossed
    struct Info {
        bool initialized;
        uint128 liquidityGross;
        int128 liquidityNet;
    }

    /// @notice Updates the tick information with a liquidity delta
    /// @param self The mapping containing tick information
    /// @param tick The specific tick to update
    /// @param liquidityDelta The change in liquidity for the tick
    /// @param upper Whether the tick is the upper bound of a range
    /// @return flipped Whether the tick was flipped (from uninitialized to initialized or vice versa)
    function update(mapping(int24 => Tick.Info) storage self, int24 tick, int128 liquidityDelta, bool upper)
        internal
        returns (bool flipped)
    {
        Tick.Info storage tickInfo = self[tick];

        uint128 liquidityBefore = tickInfo.liquidityGross;
        uint128 liquidityAfter = LiquidityMath.addLiquidity(liquidityBefore, liquidityDelta);

        flipped = (liquidityAfter == 0) != (liquidityBefore == 0);

        if (liquidityBefore == 0) {
            tickInfo.initialized = true;
        }

        tickInfo.liquidityGross = liquidityAfter;
        tickInfo.liquidityNet = upper
            ? int128(int256(tickInfo.liquidityNet) - liquidityDelta)
            : int128(int256(tickInfo.liquidityNet) + liquidityDelta);
    }

    /// @notice Retrieves the net liquidity change for a tick when it is crossed
    /// @param self The mapping containing tick information
    /// @param tick The specific tick to query
    /// @return liquidityDelta The net liquidity change when the tick is crossed
    function cross(mapping(int24 => Tick.Info) storage self, int24 tick)
        internal
        view
        returns (int128 liquidityDelta)
    {
        Tick.Info storage info = self[tick];
        liquidityDelta = info.liquidityNet;
    }
}
