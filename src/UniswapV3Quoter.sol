// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IUniswapV3Pool } from "./interfaces/IUniswapV3Pool.sol";
import { TickMath } from "./libraries/TickMath.sol";

/// @title UniswapV3Quoter
/// @notice A contract for quoting swap information from a Uniswap V3 pool.
contract UniswapV3Quoter {
    struct QuoteParams {
        address pool; // Address of the Uniswap V3 pool contract.
        uint256 amountIn; // Input amount for the swap.
        uint160 sqrtPriceLimitX96;
        bool zeroForOne; // If true, token0 is the input, otherwise token1 is the input.
    }

    /// @notice Quotes swap information from a Uniswap V3 pool.
    /// @param params The parameters for the quote, including pool address, input amount, and swap direction.
    /// @return amountOut The output amount of the swap.
    /// @return sqrtPriceX96After The square root of the price after the swap.
    /// @return tickAfter The tick value after the swap.
    function quote(QuoteParams memory params)
        public
        returns (uint256 amountOut, uint160 sqrtPriceX96After, int24 tickAfter)
    {
        try IUniswapV3Pool(params.pool).swap(
            address(this),
            params.zeroForOne,
            params.amountIn,
            params.sqrtPriceLimitX96 == 0
                ? (params.zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : params.sqrtPriceLimitX96,
            abi.encode(params.pool)
        ) { } catch (bytes memory reason) {
            return abi.decode(reason, (uint256, uint160, int24));
        }
    }

    /// @notice Callback function for handling swap callbacks from a Uniswap V3 pool.
    /// @param amount0Delta The change in amount of token0 after the swap.
    /// @param amount1Delta The change in amount of token1 after the swap.
    /// @param data Additional data encoded using abi.encode().
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes memory data) external view {
        address pool = abi.decode(data, (address));
        // Collecting values: output amount, new price, and corresponding tick
        uint256 amountOut = amount0Delta > 0 ? uint256(-amount1Delta) : uint256(-amount0Delta);

        (uint160 sqrtPriceX96After, int24 tickAfter) = IUniswapV3Pool(pool).slot0();

        // Save values and revert
        assembly {
            let ptr := mload(0x40) // Reads the pointer of the next available memory slot
            mstore(ptr, amountOut) // Writes amountOut at that memory slot
            mstore(add(ptr, 0x20), sqrtPriceX96After) // Writes sqrtPriceX96After right after amountOut
            mstore(add(ptr, 0x40), tickAfter) // Writes tickAfter after sqrtPriceX96After
            revert(ptr, 96) // Reverts the call and returns 96 bytes (total length of the values written to memory)
                // of data at address ptr (start of the data written above).
        }
    }
}
