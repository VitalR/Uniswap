// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { UniswapV3Pool } from "./UniswapV3Pool.sol";
import { IERC20 } from "./interfaces/IERC20.sol";

/// @title UniswapV3Manager
/// @notice This contract works with any Uniswap V3 pool, allowing any address to interact with it.
///         The manager contract serves as a simple intermediary, redirecting calls to a specific pool contract.
contract UniswapV3Manager {
    /// @notice Mint function for providing liquidity to a Uniswap V3 pool.
    /// @param poolAddress The address of the Uniswap V3 pool contract.
    /// @param lowerTick The lower tick of the liquidity range.
    /// @param upperTick The upper tick of the liquidity range.
    /// @param liquidity The amount of liquidity to be provided.
    /// @param data Additional data encoded using abi.encode().
    /// @return amount0 The amount of token0 minted.
    /// @return amount1 The amount of token1 minted.
    function mint(address poolAddress, int24 lowerTick, int24 upperTick, uint128 liquidity, bytes calldata data)
        public
        returns (uint256, uint256)
    {
        return UniswapV3Pool(poolAddress).mint(msg.sender, lowerTick, upperTick, liquidity, data);
    }

    /// @notice Swap function for swapping tokens on a Uniswap V3 pool.
    /// @param poolAddress The address of the Uniswap V3 pool contract.
    /// @param zeroForOne If true, token0 is the input, otherwise token1 is the input.
    /// @param amountSpecified The specified input or output amount, depending on the direction of the swap.
    /// @param data Additional data encoded using abi.encode().
    /// @return amount0 The amount of token0 swapped.
    /// @return amount1 The amount of token1 swapped.
    function swap(address poolAddress, bool zeroForOne, uint256 amountSpecified, bytes calldata data)
        public
        returns (int256, int256)
    {
        return UniswapV3Pool(poolAddress).swap(msg.sender, zeroForOne, amountSpecified, data);
    }

    /// @notice Callback function for handling mint callbacks from a Uniswap V3 pool.
    /// @param amount0 The amount of token0 minted.
    /// @param amount1 The amount of token1 minted.
    /// @param data Additional data encoded using abi.encode().
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata data) public {
        UniswapV3Pool.CallbackData memory extra = abi.decode(data, (UniswapV3Pool.CallbackData));
        IERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0);
        IERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1);
    }

    /// @notice Callback function for handling swap callbacks from a Uniswap V3 pool.
    /// @param amount0 The amount of token0 swapped.
    /// @param amount1 The amount of token1 swapped.
    /// @param data Additional data encoded using abi.encode().
    function uniswapV3SwapCallback(int256 amount0, int256 amount1, bytes calldata data) public {
        UniswapV3Pool.CallbackData memory extra = abi.decode(data, (UniswapV3Pool.CallbackData));
        if (amount0 > 0) {
            IERC20(extra.token0).transferFrom(extra.payer, msg.sender, uint256(amount0));
        }
        if (amount1 > 0) {
            IERC20(extra.token1).transferFrom(extra.payer, msg.sender, uint256(amount1));
        }
    }
}
