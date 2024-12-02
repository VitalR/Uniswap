// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IUniswapV3Manager {
    error SlippageCheckFailed(uint256 amount0, uint256 amount1);

    /// @notice Mint function for providing liquidity to a Uniswap V3 pool.
    /// @param poolAddress The address of the Uniswap V3 pool contract.
    /// @param lowerTick The lower tick of the liquidity range.
    /// @param upperTick The upper tick of the liquidity range.
    /// @param amount0Desired The amount of liquidity to be provided.
    /// @param amount1Desired The amount of liquidity to be provided.
    /// @return amount0Min The amount of token0 calculated and minted based on slippage tolerance.
    /// @return amount1Min The amount of token1 calculated and minted based on slippage tolerance.
    struct MintParams {
        address poolAddress;
        int24 lowerTick;
        int24 upperTick;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }
}