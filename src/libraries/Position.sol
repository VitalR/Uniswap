// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import "prb-math/Common.sol";
import { FixedPoint128 } from "./FixedPoint128.sol";
import { LiquidityMath } from "./LiquidityMath.sol";

/// @title Position Library
/// @notice A library for managing and updating liquidity positions in Uniswap V3 pools.
/// @dev Provides functionality to track and update position-related data, including liquidity and accrued fees.
library Position {
    /// @notice Represents information about a liquidity position.
    /// @dev Contains details about liquidity, fee growth, and tokens owed.
    /// @param liquidity The total liquidity associated with the position.
    /// @param feeGrowthInside0LastX128 The last recorded fee growth for token0 inside the position's range.
    /// @param feeGrowthInside1LastX128 The last recorded fee growth for token1 inside the position's range.
    /// @param tokensOwed0 The amount of token0 owed to the position.
    /// @param tokensOwed1 The amount of token1 owed to the position.
    struct Info {
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    /// @notice Updates the liquidity and fee-related information of a position.
    /// @dev Adjusts the position's liquidity based on the provided delta and updates fee growth and tokens owed.
    ///      Fee growth calculations assume that `feeGrowthInside0X128` and `feeGrowthInside1X128` are cumulative.
    /// @param self The storage pointer to the position being updated.
    /// @param liquidityDelta The change in liquidity to apply to the position. Can be positive (add liquidity) or
    /// negative (remove liquidity).
    /// @param feeGrowthInside0X128 The current cumulative fee growth for token0 inside the position's range.
    /// @param feeGrowthInside1X128 The current cumulative fee growth for token1 inside the position's range.
    function update(
        Info storage self,
        int128 liquidityDelta,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) internal {
        uint128 tokensOwed0 =
            uint128(mulDiv(feeGrowthInside0X128 - self.feeGrowthInside0LastX128, self.liquidity, FixedPoint128.Q128));
        uint128 tokensOwed1 =
            uint128(mulDiv(feeGrowthInside1X128 - self.feeGrowthInside1LastX128, self.liquidity, FixedPoint128.Q128));

        self.liquidity = LiquidityMath.addLiquidity(self.liquidity, liquidityDelta);
        self.feeGrowthInside0LastX128 = feeGrowthInside0X128;
        self.feeGrowthInside1LastX128 = feeGrowthInside1X128;

        if (tokensOwed0 > 0 || tokensOwed1 > 0) {
            self.tokensOwed0 += tokensOwed0;
            self.tokensOwed1 += tokensOwed1;
        }
    }

    /// @notice Retrieves a specific position using the owner address and tick range
    /// @param self The mapping of positions
    /// @param owner The address of the position owner
    /// @param lowerTick The lower tick boundary of the position
    /// @param upperTick The upper tick boundary of the position
    /// @return position The position information
    function get(mapping(bytes32 => Info) storage self, address owner, int24 lowerTick, int24 upperTick)
        internal
        view
        returns (Position.Info storage position)
    {
        position = self[keccak256(abi.encodePacked(owner, lowerTick, upperTick))];
    }
}
