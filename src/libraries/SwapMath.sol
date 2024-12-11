// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "prb-math/Common.sol";
import { Math } from "./Math.sol";

/// @title SwapMath Library
/// @notice Contains logic for computing swap steps in a Uniswap
library SwapMath {
    /// @notice Computes the next price and token amounts for a swap step.
    /// @dev The function calculates the new square root price (`sqrtPriceNextX96`) based on the provided input amount,
    ///      liquidity, and fee, as well as the token amounts exchanged and the fees incurred in the step.
    /// @param sqrtPriceCurrentX96 The current square root price as a Q96.96 value.
    /// @param sqrtPriceTargetX96 The target square root price as a Q96.96 value.
    /// @param liquidity The current liquidity available in the range.
    /// @param amountRemaining The remaining amount of input token available for the swap.
    /// @param fee The fee rate for the swap, expressed in hundredths of a bip (e.g., 500 = 0.05%).
    /// @return sqrtPriceNextX96 The next square root price after the swap step.
    /// @return amountIn The amount of input token used during the swap step.
    /// @return amountOut The amount of output token obtained during the swap step.
    /// @return feeAmount The fee amount deducted during the swap step.
    function computeSwapStep(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        uint256 amountRemaining,
        uint24 fee
    ) internal pure returns (uint160 sqrtPriceNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount) {
        bool zeroForOne = sqrtPriceCurrentX96 >= sqrtPriceTargetX96;

        uint256 amountRemainingLessFee = mulDiv(
            amountRemaining,
            1e6 - fee,
            1e6
        );

        amountIn = zeroForOne
            ? Math.calcAmount0Delta(
                sqrtPriceCurrentX96,
                sqrtPriceTargetX96,
                liquidity,
                true
            )
            : Math.calcAmount1Delta(
                sqrtPriceCurrentX96,
                sqrtPriceTargetX96,
                liquidity,
                true
            );

        if (amountRemainingLessFee >= amountIn)
            sqrtPriceNextX96 = sqrtPriceTargetX96;
        else
            sqrtPriceNextX96 = Math.getNextSqrtPriceFromInput(
                sqrtPriceCurrentX96,
                liquidity,
                amountRemainingLessFee,
                zeroForOne
            );

        bool max = sqrtPriceNextX96 == sqrtPriceTargetX96;

        if (zeroForOne) {
            amountIn = max
                ? amountIn
                : Math.calcAmount0Delta(
                    sqrtPriceCurrentX96,
                    sqrtPriceNextX96,
                    liquidity,
                    true
                );
            amountOut = Math.calcAmount1Delta(
                sqrtPriceCurrentX96,
                sqrtPriceNextX96,
                liquidity,
                false
            );
        } else {
            amountIn = max
                ? amountIn
                : Math.calcAmount1Delta(
                    sqrtPriceCurrentX96,
                    sqrtPriceNextX96,
                    liquidity,
                    true
                );
            amountOut = Math.calcAmount0Delta(
                sqrtPriceCurrentX96,
                sqrtPriceNextX96,
                liquidity,
                false
            );
        }

        if (!max) {
            feeAmount = amountRemaining - amountIn;
        } else {
            feeAmount = Math.mulDivRoundingUp(amountIn, fee, 1e6 - fee);
        }
    }
}
