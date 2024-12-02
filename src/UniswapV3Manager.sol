// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IUniswapV3Manager } from "./interfaces/IUniswapV3Manager.sol";
import { IUniswapV3Pool } from "./interfaces/IUniswapV3Pool.sol";
import { UniswapV3Pool } from "./UniswapV3Pool.sol";
import { IERC20 } from "./interfaces/IERC20.sol";

import { LiquidityMath } from "src/libraries/LiquidityMath.sol";
import { TickMath } from "src/libraries/TickMath.sol";

/// @title UniswapV3Manager
/// @notice This contract works with any Uniswap V3 pool, allowing any address to interact with it.
/// The manager contract serves as a simple intermediary, redirecting calls to a specific pool contract.
contract UniswapV3Manager is IUniswapV3Manager {
    // / @notice Mint function for providing liquidity to a Uniswap V3 pool.
    function mint(MintParams calldata params) public returns (uint256 amount0, uint256 amount1) {
        IUniswapV3Pool pool = IUniswapV3Pool(params.poolAddress);

        (uint160 sqrtPriceX96,) = pool.slot0();
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(params.lowerTick);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(params.upperTick);

        uint128 liquidity = LiquidityMath.getLiquidityForAmounts(
            sqrtPriceX96, sqrtPriceLowerX96, sqrtPriceUpperX96, params.amount0Desired, params.amount1Desired
        );

        (amount0, amount1) = pool.mint(
            msg.sender,
            params.lowerTick,
            params.upperTick,
            liquidity,
            abi.encode(IUniswapV3Pool.CallbackData({ token0: pool.token0(), token1: pool.token1(), payer: msg.sender }))
        );

        if (amount0 < params.amount0Min || amount1 < params.amount1Min) {
            revert SlippageCheckFailed(amount0, amount1);
        }
    }

    /// @notice Swap function for swapping tokens on a Uniswap V3 pool.
    /// @param poolAddress The address of the Uniswap V3 pool contract.
    /// @param zeroForOne If true, token0 is the input, otherwise token1 is the input.
    /// @param amountSpecified The specified input or output amount, depending on the direction of the swap.
    /// @param sqrtPriceLimitX96 ...
    /// @param data Additional data encoded using abi.encode().
    /// @return amount0 The amount of token0 swapped.
    /// @return amount1 The amount of token1 swapped.
    function swap(
        address poolAddress,
        bool zeroForOne,
        uint256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) public returns (int256, int256) {
        return UniswapV3Pool(poolAddress).swap(
            msg.sender,
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : sqrtPriceLimitX96,
            data
        );
    }

    /// @notice Callback function for handling mint callbacks from a Uniswap V3 pool.
    /// @param amount0 The amount of token0 minted.
    /// @param amount1 The amount of token1 minted.
    /// @param data Additional data encoded using abi.encode().
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata data) public {
        UniswapV3Pool.CallbackData memory extra = abi.decode(data, (IUniswapV3Pool.CallbackData));
        IERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0);
        IERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1);
    }

    /// @notice Callback function for handling swap callbacks from a Uniswap V3 pool.
    /// @param amount0 The amount of token0 swapped.
    /// @param amount1 The amount of token1 swapped.
    /// @param data Additional data encoded using abi.encode().
    function uniswapV3SwapCallback(int256 amount0, int256 amount1, bytes calldata data) public {
        UniswapV3Pool.CallbackData memory extra = abi.decode(data, (IUniswapV3Pool.CallbackData));
        if (amount0 > 0) {
            IERC20(extra.token0).transferFrom(extra.payer, msg.sender, uint256(amount0));
        }
        if (amount1 > 0) {
            IERC20(extra.token1).transferFrom(extra.payer, msg.sender, uint256(amount1));
        }
    }
}
