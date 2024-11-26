// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.25;

/// @title IUniswapV3Pool
/// @notice Interface for a Uniswap V3 pool contract.
interface IUniswapV3Pool {
    /// @notice Retrieves the current slot0 values from the Uniswap V3 pool.
    /// @return sqrtPriceX96 The square root of the price multiplied by 2^96.
    /// @return tick The current tick value.
    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick);

    /// @notice Mints liquidity in the Uniswap V3 pool within a specified tick range.
    /// @param owner The address that will own the minted liquidity.
    /// @param lowerTick The lower tick of the desired price range.
    /// @param upperTick The upper tick of the desired price range.
    /// @param amount The amount of liquidity to be minted.
    /// @param data Additional data encoded using abi.encode().
    /// @return amount0 The amount of token0 minted.
    /// @return amount1 The amount of token1 minted.
    function mint(address owner, int24 lowerTick, int24 upperTick, uint128 amount, bytes calldata data)
        external
        returns (uint256 amount0, uint256 amount1);

    /// @notice Swaps tokens in the Uniswap V3 pool.
    /// @param recipient The address that will receive the swapped tokens.
    /// @param zeroForOne If true, token0 is the input, otherwise token1 is the input.
    /// @param amountSpecified The specified input or output amount, depending on the direction of the swap.
    /// @param data Additional data encoded using abi.encode().
    /// @return amount0 The amount of token0 swapped.
    /// @return amount1 The amount of token1 swapped.
    function swap(address recipient, bool zeroForOne, uint256 amountSpecified, bytes calldata data)
        external
        returns (int256 amount0, int256 amount1);
}
