// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title IUniswapV3Manager
/// @notice Interface for managing liquidity and performing swaps in Uniswap V3 pools.
interface IUniswapV3Manager {
    /// @notice Thrown when a slippage check fails during a mint or swap operation.
    /// @param amount0 The actual amount of token0 involved in the transaction.
    /// @param amount1 The actual amount of token1 involved in the transaction.
    error SlippageCheckFailed(uint256 amount0, uint256 amount1);

    /// @notice Thrown when the output amount of a swap is less than the specified minimum.
    /// @param amountOut The actual output amount of the swap.
    error TooLittleReceived(uint256 amountOut);

    /// @notice Parameters for fetching position information.
    /// @param tokenA The address of the first token in the pair.
    /// @param tokenB The address of the second token in the pair.
    /// @param fee The fee tier of the pool (e.g., 500 for 0.05%, 3000 for 0.3%).
    /// @param owner The address of the position owner.
    /// @param lowerTick The lower tick of the position's range.
    /// @param upperTick The upper tick of the position's range.
    struct GetPositionParams {
        address tokenA;
        address tokenB;
        uint24 fee;
        address owner;
        int24 lowerTick;
        int24 upperTick;
    }

    /// @notice Parameters for minting liquidity to a Uniswap V3 pool.
    /// @param tokenA The address of the first token in the pair.
    /// @param tokenB The address of the second token in the pair.
    /// @param fee The fee tier of the pool (e.g., 500 for 0.05%, 3000 for 0.3%).
    /// @param lowerTick The lower tick of the liquidity range.
    /// @param upperTick The upper tick of the liquidity range.
    /// @param amount0Desired The desired amount of token0 to provide as liquidity.
    /// @param amount1Desired The desired amount of token1 to provide as liquidity.
    /// @param amount0Min The minimum amount of token0 to accept after slippage.
    /// @param amount1Min The minimum amount of token1 to accept after slippage.
    struct MintParams {
        address tokenA;
        address tokenB;
        uint24 fee;
        int24 lowerTick;
        int24 upperTick;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    /// @notice Parameters for performing a single swap in a Uniswap V3 pool.
    /// @param tokenIn The address of the input token.
    /// @param tokenOut The address of the output token.
    /// @param fee The fee tier of the pool (e.g., 500 for 0.05%, 3000 for 0.3%).
    /// @param amountIn The amount of input token to swap.
    /// @param sqrtPriceLimitX96 The square root price limit for the swap, as a Q64.96 value.
    struct SwapSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        uint256 amountIn;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Parameters for performing a multi-hop swap in a Uniswap V3 pool.
    /// @param path The encoded swap path, consisting of token addresses and fee tiers.
    /// @param recipient The address to receive the output tokens.
    /// @param amountIn The amount of input token to swap.
    /// @param minAmountOut The minimum amount of output token to accept after the swap.
    struct SwapParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 minAmountOut;
    }

    /// @notice Callback data for swap operations.
    /// @param path The encoded swap path, consisting of token addresses and fee tiers.
    /// @param payer The address responsible for paying for the swap.
    struct SwapCallbackData {
        bytes path;
        address payer;
    }
}
