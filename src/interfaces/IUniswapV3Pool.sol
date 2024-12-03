// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.25;

/// @notice Interface for a Uniswap V3 pool contract defining the core methods and events.
/// @dev This interface outlines the essential functionalities of a Uniswap V3 pool, including managing liquidity,
///      executing swaps, and interacting with callback mechanisms for token transfers.
///      It includes errors and data structures necessary for pool operations and safety checks.
interface IUniswapV3Pool {
    /// @dev Custom Errors
    error AlreadyInitialized();
    error InsufficientInputAmount();
    error InvalidTickRange();
    error InvalidPriceLimit();
    error NotEnoughLiquidity();
    error ZeroLiquidity();

    struct CallbackData {
        /// @notice The address of token0 in the pool.
        address token0;
        /// @notice The address of token1 in the pool.
        address token1;
        /// @notice The address responsible for the token transfer in callback functions.
        address payer;
    }

    /// @notice Emitted when liquidity is minted.
    /// @param sender The address that initiated the mint.
    /// @param owner The owner of the minted liquidity.
    /// @param lowerTick The lower tick of the liquidity range.
    /// @param upperTick The upper tick of the liquidity range.
    /// @param amount The amount of liquidity minted.
    /// @param amount0 The amount of token0 added as liquidity.
    /// @param amount1 The amount of token1 added as liquidity.
    event Mint(
        address sender,
        address owner,
        int24 lowerTick,
        int24 upperTick,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when a swap occurs.
    /// @param sender The address that initiated the swap.
    /// @param recipient The recipient of the swapped tokens.
    /// @param amount0 The net change in token0 during the swap.
    /// @param amount1 The net change in token1 during the swap.
    /// @param sqrtPriceX96 The pool's price after the swap.
    /// @param liquidity The pool's liquidity after the swap.
    /// @param tick The pool's tick after the swap.
    event Swap(
        address sender,
        address recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    /// @notice Emitted when a flash loan is executed.
    /// @param sender The address that initiated the flash loan.
    /// @param amount0 The amount of token0 borrowed in the flash loan.
    /// @param amount1 The amount of token1 borrowed in the flash loan.
    event Flash(address indexed sender, uint256 amount0, uint256 amount1);

    /// @notice Retrieves the current slot0 values from the Uniswap V3 pool.
    /// @return sqrtPriceX96 The square root of the price multiplied by 2^96.
    /// @return tick The current tick value.
    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick);

    /// @notice Fetches the balance of token0 held by the pool.
    function token0() external view returns (address);

    /// @notice Fetches the balance of token1 held by the pool.
    function token1() external view returns (address);

    /// @notice Mints liquidity for the given range in the pool.
    /// @param owner The address that will own the minted liquidity.
    /// @param lowerTick The lower tick of the liquidity range.
    /// @param upperTick The upper tick of the liquidity range.
    /// @param amount The amount of liquidity to mint.
    /// @param data Encoded data for the mint callback.
    /// @return amount0 The actual amount of token0 used for the mint.
    /// @return amount1 The actual amount of token1 used for the mint.
    function mint(address owner, int24 lowerTick, int24 upperTick, uint128 amount, bytes calldata data)
        external
        returns (uint256 amount0, uint256 amount1);

    /// @notice Swaps tokens within the pool.
    /// @param recipient The address to receive the swapped tokens.
    /// @param zeroForOne If true, token0 is swapped for token1; otherwise, token1 is swapped for token0.
    /// @param amountSpecified The specified input or output amount for the swap.
    /// @param sqrtPriceLimitX96 The price limit for the swap in sqrt(P) format.
    /// @param data Encoded data for the swap callback.
    /// @return amount0 The net change in token0 during the swap.
    /// @return amount1 The net change in token1 during the swap.
    function swap(
        address recipient,
        bool zeroForOne,
        uint256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}
