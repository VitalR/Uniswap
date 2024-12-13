// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { LiquidityMath } from "src/libraries/LiquidityMath.sol";
import { Math } from "src/libraries/Math.sol";

/// @title Tick Library
/// @notice Provides functions for managing tick-level state in an automated market maker (AMM).
/// @dev This library handles the state of liquidity and fee growth at individual ticks within a Uniswap V3 pool.
library Tick {
    /// @notice Represents the state of a single tick.
    /// @param initialized Indicates whether the tick has been initialized.
    /// @param liquidityGross The total liquidity at the tick.
    /// @param liquidityNet The net change in liquidity when the tick is crossed.
    /// @param feeGrowthOutside0X128 The cumulative fee growth of token0 outside the tick range.
    /// @param feeGrowthOutside1X128 The cumulative fee growth of token1 outside the tick range.
    struct Info {
        bool initialized;
        uint128 liquidityGross;
        int128 liquidityNet;
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
    }

    /// @notice Updates the tick information with a liquidity delta.
    /// @dev This function adjusts the gross and net liquidity at a tick and updates the fee growth if the tick
    ///      transitions from uninitialized to initialized.
    /// @param self The mapping containing tick information.
    /// @param tick The specific tick to update.
    /// @param currentTick The current tick of the pool.
    /// @param liquidityDelta The change in liquidity for the tick. Can be positive (adding liquidity) or negative
    /// (removing liquidity).
    /// @param feeGrowthGlobal0X128 The current global fee growth of token0.
    /// @param feeGrowthGlobal1X128 The current global fee growth of token1.
    /// @param upper Indicates whether the tick is the upper bound of a liquidity range.
    /// @return flipped Indicates whether the tick's initialization state was flipped (initialized/uninitialized).
    function update(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        int24 currentTick,
        int128 liquidityDelta,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        bool upper
    ) internal returns (bool flipped) {
        Tick.Info storage tickInfo = self[tick];

        uint128 liquidityBefore = tickInfo.liquidityGross;
        uint128 liquidityAfter = LiquidityMath.addLiquidity(liquidityBefore, liquidityDelta);

        flipped = (liquidityAfter == 0) != (liquidityBefore == 0);

        if (liquidityBefore == 0) {
            // by convention, assume that all previous fees were collected below
            // the tick
            if (tick <= currentTick) {
                tickInfo.feeGrowthOutside0X128 = feeGrowthGlobal0X128;
                tickInfo.feeGrowthOutside1X128 = feeGrowthGlobal1X128;
            }

            tickInfo.initialized = true;
        }

        tickInfo.liquidityGross = liquidityAfter;
        tickInfo.liquidityNet = upper
            ? int128(int256(tickInfo.liquidityNet) - liquidityDelta)
            : int128(int256(tickInfo.liquidityNet) + liquidityDelta);
    }

    /// @notice Retrieves the net liquidity change for a tick when it is crossed.
    /// @dev This function updates the fee growth outside the tick range and returns the net liquidity change.
    /// @param self The mapping containing tick information.
    /// @param tick The specific tick to query.
    /// @param feeGrowthGlobal0X128 The current global fee growth of token0.
    /// @param feeGrowthGlobal1X128 The current global fee growth of token1.
    /// @return liquidityDelta The net liquidity change when the tick is crossed.
    function cross(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal returns (int128 liquidityDelta) {
        Tick.Info storage info = self[tick];
        info.feeGrowthOutside0X128 = feeGrowthGlobal0X128 - info.feeGrowthOutside0X128;
        info.feeGrowthOutside1X128 = feeGrowthGlobal1X128 - info.feeGrowthOutside1X128;
        liquidityDelta = info.liquidityNet;
    }

    /// @notice Calculates the fee growth within a specific range of ticks.
    /// @dev This function considers fee growth below and above the range to compute the growth inside.
    /// @param self The mapping containing tick information.
    /// @param lowerTick_ The lower tick of the range.
    /// @param upperTick_ The upper tick of the range.
    /// @param currentTick The current tick of the pool.
    /// @param feeGrowthGlobal0X128 The current global fee growth of token0.
    /// @param feeGrowthGlobal1X128 The current global fee growth of token1.
    /// @return feeGrowthInside0X128 The fee growth of token0 inside the range.
    /// @return feeGrowthInside1X128 The fee growth of token1 inside the range.
    function getFeeGrowthInside(
        mapping(int24 => Tick.Info) storage self,
        int24 lowerTick_,
        int24 upperTick_,
        int24 currentTick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        Tick.Info storage lowerTick = self[lowerTick_];
        Tick.Info storage upperTick = self[upperTick_];

        uint256 feeGrowthBelow0X128;
        uint256 feeGrowthBelow1X128;
        if (currentTick >= lowerTick_) {
            feeGrowthBelow0X128 = lowerTick.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = lowerTick.feeGrowthOutside1X128;
        } else {
            feeGrowthBelow0X128 = feeGrowthGlobal0X128 - lowerTick.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = feeGrowthGlobal1X128 - lowerTick.feeGrowthOutside1X128;
        }

        uint256 feeGrowthAbove0X128;
        uint256 feeGrowthAbove1X128;
        if (currentTick < upperTick_) {
            feeGrowthAbove0X128 = upperTick.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = upperTick.feeGrowthOutside1X128;
        } else {
            feeGrowthAbove0X128 = feeGrowthGlobal0X128 - upperTick.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = feeGrowthGlobal1X128 - upperTick.feeGrowthOutside1X128;
        }

        feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
        feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }
}
