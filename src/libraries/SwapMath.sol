// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { Math } from "./Math.sol";

/// @title SwapMath Library
/// @notice Contains logic for computing swap steps in a Uniswap
library SwapMath {
    /// @notice Computes the next price and token amounts for a swap step
    /// @param sqrtPriceCurrentX96 The current square root price as a Q96.96 value
    /// @param sqrtPriceTargetX96 The target square root price as a Q96.96 value
    /// @param liquidity The current liquidity available in the range
    /// @param amountRemaining The remaining amount of input token
    /// @return sqrtPriceNextX96 The next square root price
    /// @return amountIn The amount of input token used in the step
    /// @return amountOut The amount of output token obtained in the step
    function computeSwapStep(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        uint256 amountRemaining
    ) internal pure returns (uint160 sqrtPriceNextX96, uint256 amountIn, uint256 amountOut) {
        bool zeroForOne = sqrtPriceCurrentX96 >= sqrtPriceTargetX96;

        amountIn = zeroForOne
            ? Math.calcAmount0Delta(sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity)
            : Math.calcAmount1Delta(sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity);

        if (amountRemaining >= amountIn) {
            sqrtPriceNextX96 = sqrtPriceTargetX96;
        } else {
            sqrtPriceNextX96 =
                Math.getNextSqrtPriceFromInput(sqrtPriceCurrentX96, liquidity, amountRemaining, zeroForOne);
        }

        amountIn = Math.calcAmount0Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity);

        amountOut = Math.calcAmount1Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity);

        if (!zeroForOne) {
            (amountIn, amountOut) = (amountOut, amountIn);
        }
    }
}
