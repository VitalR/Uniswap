// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/token/ERC20/IERC20.sol";

import { IUniswapV3Manager } from "./interfaces/IUniswapV3Manager.sol";
import { UniswapV3Pool, IUniswapV3Pool } from "./UniswapV3Pool.sol";

import { LiquidityMath } from "src/libraries/LiquidityMath.sol";
import { Path } from "src/libraries/Path.sol";
import { PoolAddress } from "src/libraries/PoolAddress.sol";
import { TickMath } from "src/libraries/TickMath.sol";

/// @title UniswapV3Manager
/// @notice This contract works with any Uniswap V3 pool, allowing any address to interact with it.
/// The manager contract serves as a simple intermediary, redirecting calls to a specific pool contract.
contract UniswapV3Manager is IUniswapV3Manager {
    using Path for bytes;

    /// @notice The address of the factory.
    address public immutable factory;

    /// @notice Constructor initializes the manager parameters.
    constructor(address _factory) {
        factory = _factory;
    }

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
        address poolAddress = PoolAddress.computeAddress(factory, params.tokenA, params.tokenB, params.tickSpacing);
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

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

    /// @notice Executes a single-pool swap on a Uniswap V3 pool.
    /// @dev This function swaps tokens based on the specified parameters and returns the output amount.
    /// @param params The parameters for the swap, encapsulated in a `SwapSingleParams` struct:
    ///        - tokenIn: The address of the input token.
    ///        - tokenOut: The address of the output token.
    ///        - tickSpacing: The tick spacing of the pool.
    ///        - amountIn: The amount of the input token to swap.
    ///        - sqrtPriceLimitX96: The sqrt price limit for the swap. Use 0 for default behavior.
    /// @return amountOut The amount of the output token received from the swap.
    function swapSingle(SwapSingleParams calldata params) public returns (uint256 amountOut) {
        amountOut = _swap(
            params.amountIn,
            msg.sender,
            params.sqrtPriceLimitX96,
            SwapCallbackData({
                path: abi.encodePacked(params.tokenIn, params.tickSpacing, params.tokenOut),
                payer: msg.sender
            })
        );
    }

    /// @notice Executes a multi-hop swap across multiple Uniswap V3 pools.
    /// @dev This function iterates through the path to swap tokens across multiple pools.
    ///      Reverts if the received output amount is less than the minimum specified.
    /// @param params The parameters for the swap, encapsulated in a `SwapParams` struct:
    ///        - path: The encoded swap path (token addresses and tick spacings).
    ///        - amountIn: The amount of the input token to swap.
    ///        - recipient: The address to receive the output tokens.
    ///        - minAmountOut: The minimum amount of output tokens expected.
    /// @return amountOut The total amount of output tokens received from the swap.
    function swap(SwapParams memory params) public returns (uint256 amountOut) {
        address payer = msg.sender;
        bool hasMultiplePools;

        while (true) {
            hasMultiplePools = params.path.hasMultiplePools();

            params.amountIn = _swap(
                params.amountIn,
                hasMultiplePools ? address(this) : params.recipient,
                0,
                SwapCallbackData({ path: params.path.getFirstPool(), payer: payer })
            );

            if (hasMultiplePools) {
                payer = address(this);
                params.path = params.path.skipToken();
            } else {
                amountOut = params.amountIn;
                break;
            }
        }

        if (amountOut < params.minAmountOut) {
            revert TooLittleReceived(amountOut);
        }
    }

    /// @notice Internal function to perform a single swap operation.
    /// @dev This function interacts with the specified pool to execute a token swap.
    /// @param amountIn The amount of the input token to swap.
    /// @param recipient The address to receive the output tokens.
    /// @param sqrtPriceLimitX96 The Q64.96 sqrt price limit for the swap. If set to zero, it uses default values:
    ///        - For zeroForOne = true: TickMath.MIN_SQRT_RATIO + 1.
    ///        - For zeroForOne = false: TickMath.MAX_SQRT_RATIO - 1.
    /// @param data Callback data containing the swap path and payer information.
    /// @return amountOut The amount of the output token received from the swap.
    function _swap(uint256 amountIn, address recipient, uint160 sqrtPriceLimitX96, SwapCallbackData memory data)
        internal
        returns (uint256 amountOut)
    {
        (address tokenIn, address tokenOut, uint24 tickSpacing) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0, int256 amount1) = getPool(tokenIn, tokenOut, tickSpacing).swap(
            recipient,
            zeroForOne,
            amountIn,
            sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : sqrtPriceLimitX96,
            abi.encode(data)
        );

        amountOut = uint256(-(zeroForOne ? amount1 : amount0));
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
    /// @param data_ Additional data encoded using abi.encode().
    function uniswapV3SwapCallback(int256 amount0, int256 amount1, bytes calldata data_) public {
        SwapCallbackData memory data = abi.decode(data_, (SwapCallbackData));
        (address tokenIn, address tokenOut,) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        int256 amount = zeroForOne ? amount0 : amount1;

        if (data.payer == address(this)) {
            IERC20(tokenIn).transfer(msg.sender, uint256(amount));
        } else {
            IERC20(tokenIn).transferFrom(data.payer, msg.sender, uint256(amount));
        }
    }
}
