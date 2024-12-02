// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/token/ERC20/IERC20.sol";

import { IUniswapV3Manager } from "./interfaces/IUniswapV3Manager.sol";
import { UniswapV3Pool, IUniswapV3Pool } from "./UniswapV3Pool.sol";

import { LiquidityMath } from "src/libraries/LiquidityMath.sol";
import { TickMath } from "src/libraries/TickMath.sol";

/// @title UniswapV3Manager
/// @notice This contract works with any Uniswap V3 pool, allowing any address to interact with it.
/// The manager contract serves as a simple intermediary, redirecting calls to a specific pool contract.
contract UniswapV3Manager is IUniswapV3Manager {
    /// @notice Mint function for providing liquidity to a Uniswap V3 pool.
    /// @dev This function calculates the liquidity based on the specified ticks and amounts, then mints liquidity
    ///      to the specified Uniswap V3 pool. It reverts if the slippage tolerance is exceeded.
    /// @param params The parameters required for minting liquidity, encapsulated in a `MintParams` struct:
    ///        - poolAddress: The address of the Uniswap V3 pool.
    ///        - lowerTick: The lower tick of the position.
    ///        - upperTick: The upper tick of the position.
    ///        - amount0Desired: The desired amount of token0 to add as liquidity.
    ///        - amount1Desired: The desired amount of token1 to add as liquidity.
    ///        - amount0Min: The minimum amount of token0 required to mint liquidity.
    ///        - amount1Min: The minimum amount of token1 required to mint liquidity.
    /// @return amount0 The actual amount of token0 used to mint the liquidity.
    /// @return amount1 The actual amount of token1 used to mint the liquidity.
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
    /// @dev Executes a swap on the specified Uniswap V3 pool. If `sqrtPriceLimitX96` is zero, it defaults to the minimum or maximum
    ///      sqrt price ratio depending on the swap direction.
    /// @param poolAddress The address of the Uniswap V3 pool contract.
    /// @param zeroForOne If true, token0 is the input and token1 is the output. Otherwise, token1 is the input and token0 is the output.
    /// @param amountSpecified The specified input or output amount for the swap. A positive value represents an input amount,
    ///        while a negative value represents an output amount.
    /// @param sqrtPriceLimitX96 The Q64.96 sqrt price limit for the swap. If set to zero, it uses default values:
    ///        - For zeroForOne = true: TickMath.MIN_SQRT_RATIO + 1.
    ///        - For zeroForOne = false: TickMath.MAX_SQRT_RATIO - 1.
    /// @param data Additional arbitrary data to pass to the callback function, encoded using `abi.encode`.
    /// @return amount0 The net change in token0 as a result of the swap. A positive value indicates token0 was received,
    ///         and a negative value indicates token0 was sent.
    /// @return amount1 The net change in token1 as a result of the swap. A positive value indicates token1 was received,
    ///         and a negative value indicates token1 was sent.
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
