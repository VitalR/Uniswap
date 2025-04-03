// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IUniswapV3Pool } from "./interfaces/IUniswapV3Pool.sol";
import { Path } from "src/libraries/Path.sol";
import { PoolAddress } from "src/libraries/PoolAddress.sol";
import { TickMath } from "./libraries/TickMath.sol";

/// @title UniswapV3Quoter
/// @notice A contract for quoting swap information from a Uniswap V3 pool.
/// @dev This contract provides functions to simulate swaps and retrieve details like output amounts, post-swap prices,
///      and ticks, without actually executing the swaps.
contract UniswapV3Quoter {
    using Path for bytes;

    /// @notice Struct containing parameters for a single-pool quote.
    struct QuoteSingleParams {
        /// @notice The address of the input token.
        address tokenIn;
        /// @notice The address of the output token.
        address tokenOut;
        /// @notice The fee of the pool.
        uint24 fee;
        /// @notice The input amount of the swap.
        uint256 amountIn;
        /// @notice The sqrt price limit for the swap. Use `0` for default behavior.
        uint160 sqrtPriceLimitX96;
    }

    /// @notice The address of the factory.
    address public immutable factory;

    /// @notice Constructor initializes the manager parameters.
    /// @param _factory The address of the Uniswap V3 factory contract.
    constructor(address _factory) {
        factory = _factory;
    }

    /// @notice Quotes swap information for a multi-hop swap path.
    /// @dev Iterates through the provided path, simulating swaps across multiple pools to calculate
    ///      the output amount, post-swap sqrt prices, and ticks for each hop.
    /// @param path The byte-encoded swap path.
    /// @param amountIn The input amount of the swap.
    /// @return amountOut The total output amount after completing all swaps.
    /// @return sqrtPriceX96AfterList An array of sqrt prices after each swap in the path.
    /// @return tickAfterList An array of ticks after each swap in the path.
    function quote(bytes memory path, uint256 amountIn)
        public
        returns (uint256 amountOut, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList)
    {
        sqrtPriceX96AfterList = new uint160[](path.numPools());
        tickAfterList = new int24[](path.numPools());

        uint256 i = 0;
        while (true) {
            (address tokenIn, address tokenOut, uint24 fee) = path.decodeFirstPool();

            (uint256 amountOut_, uint160 sqrtPriceX96After, int24 tickAfter) = quoteSingle(
                QuoteSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: fee,
                    amountIn: amountIn,
                    sqrtPriceLimitX96: 0
                })
            );

            sqrtPriceX96AfterList[i] = sqrtPriceX96After;
            tickAfterList[i] = tickAfter;
            amountIn = amountOut_;
            i++;

            if (path.hasMultiplePools()) {
                path = path.skipToken();
            } else {
                amountOut = amountIn;
                break;
            }
        }
    }

    /// @notice Simulates a swap on a single Uniswap V3 pool and retrieves swap details.
    /// @dev This function uses `try-catch` to handle swap simulations, decoding the results from revert reasons.
    /// @param params The parameters for the quote, encapsulated in a `QuoteSingleParams` struct.
    /// @return amountOut The output amount of the swap.
    /// @return sqrtPriceX96After The sqrt price after the swap.
    /// @return tickAfter The tick value after the swap.
    function quoteSingle(QuoteSingleParams memory params)
        public
        returns (uint256 amountOut, uint160 sqrtPriceX96After, int24 tickAfter)
    {
        IUniswapV3Pool pool = getPool(params.tokenIn, params.tokenOut, params.fee);

        bool zeroForOne = params.tokenIn < params.tokenOut;

        try pool.swap(
            address(this),
            zeroForOne,
            params.amountIn,
            params.sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : params.sqrtPriceLimitX96,
            abi.encode(address(pool))
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

        (uint160 sqrtPriceX96After, int24 tickAfter,,,) = IUniswapV3Pool(pool).slot0();

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

    /// @notice Retrieves the address of a Uniswap V3 pool for the given tokens and tick spacing.
    /// @dev Ensures that tokens are sorted (token0 < token1) before computing the pool address.
    /// @param token0 The address of the first token.
    /// @param token1 The address of the second token.
    /// @param tickSpacing The tick spacing for the pool.
    /// @return pool The address of the Uniswap V3 pool.
    function getPool(address token0, address token1, uint24 tickSpacing) internal view returns (IUniswapV3Pool pool) {
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, token0, token1, tickSpacing));
    }
}
