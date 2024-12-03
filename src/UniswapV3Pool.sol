// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/token/ERC20/IERC20.sol";

import { IUniswapV3Pool } from "./interfaces/IUniswapV3Pool.sol";
import { IUniswapV3MintCallback } from "./interfaces/IUniswapV3MintCallback.sol";
import { IUniswapV3SwapCallback } from "./interfaces/IUniswapV3SwapCallback.sol";
import { IUniswapV3FlashCallback } from "./interfaces/IUniswapV3FlashCallback.sol";

import { LiquidityMath } from "./libraries/LiquidityMath.sol";
import { Math } from "./libraries/Math.sol";
import { SwapMath } from "./libraries/SwapMath.sol";
import { Position } from "./libraries/Position.sol";
import { Tick } from "./libraries/Tick.sol";
import { TickMath } from "./libraries/TickMath.sol";
import { TickBitmap } from "./libraries/TickBitmap.sol";

/// @title UniswapV3Pool
/// @notice A Uniswap V3 pool contract that facilitates token swaps and liquidity provision with concentrated liquidity.
/// @dev This contract implements the core functionalities of a Uniswap V3 pool, including minting liquidity positions,
/// executing token swaps within defined price ranges, and managing ticks and liquidity for efficient market making.
contract UniswapV3Pool is IUniswapV3Pool {
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    ////////////////////////////////////////////////////////////////////////////
    //
    // CONFIGURATION & STORAGE
    //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Address of the first token in the pool.
    address public immutable token0;
    /// @notice Address of the second token in the pool.
    address public immutable token1;

    // First slot will contain essential data. Packing variables that are read together.
    struct Slot0 {
        /// @notice The current price of the pool in sqrt(P) format.
        uint160 sqrtPriceX96;
        /// @notice The current tick of the pool.
        int24 tick;
    }

    /// @notice The current state of the pool.
    Slot0 public slot0;

    struct SwapState {
        /// @notice The remaining amount of tokens to be swapped.
        uint256 amountSpecifiedRemaining;
        /// @notice The calculated output amount during the swap.
        uint256 amountCalculated;
        /// @notice The current sqrt price of the pool after the swap.
        uint160 sqrtPriceX96;
        /// @notice The current tick of the pool after the swap.
        int24 tick;
        /// @notice The current liquidity of the pool during the swap.
        uint128 liquidity;
    }

    struct StepState {
        /// @notice The sqrt price at the start of the swap step.
        uint160 sqrtPriceStartX96;
        /// @notice The next initialized tick to interact with.
        int24 nextTick;
        /// @notice Indicates whether the next tick is initialized.
        bool initialized;
        /// @notice The sqrt price at the next tick.
        uint160 sqrtPriceNextX96;
        /// @notice The input amount for the current step of the swap.
        uint256 amountIn;
        /// @notice The output amount for the current step of the swap.
        uint256 amountOut;
    }

    /// @notice The current liquidity of the pool.
    uint128 public liquidity;

    /// @notice Stores tick information mapped by tick indexes.
    mapping(int24 => Tick.Info) public ticks;
    /// @notice Bitmap representing initialized tick states.
    mapping(int16 => uint256) public tickBitmap;
    /// @notice Stores position information mapped by position hashes.
    mapping(bytes32 => Position.Info) public positions;

    ////////////////////////////////////////////////////////////////////////////
    //
    // CONSTRUCTOR & FUNCTIONS
    //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Constructor to initialize the pool with tokens, price, and tick.
    /// @param _token0 The address of the first token in the pool.
    /// @param _token1 The address of the second token in the pool.
    /// @param _sqrtPriceX96 The initial sqrt price of the pool.
    /// @param _tick The initial tick of the pool.
    constructor(address _token0, address _token1, uint160 _sqrtPriceX96, int24 _tick) {
        token0 = _token0;
        token1 = _token1;

        slot0 = Slot0({ sqrtPriceX96: _sqrtPriceX96, tick: _tick });
    }

    ////////////////////////////////////////////////////////////////////////////
    //
    // EXTERNAL & CORE LOGIC
    //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Mints liquidity for the given range in the pool.
    /// @dev Updates the position and pool's liquidity. Emits a Mint event on success.
    /// @param owner The address that will own the minted liquidity.
    /// @param lowerTick The lower tick of the liquidity range.
    /// @param upperTick The upper tick of the liquidity range.
    /// @param amount The amount of liquidity to mint.
    /// @param data Encoded data for the mint callback.
    /// @return amount0 The actual amount of token0 used for the mint.
    /// @return amount1 The actual amount of token1 used for the mint.
    function mint(address owner, int24 lowerTick, int24 upperTick, uint128 amount, bytes calldata data)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        // check the ticks
        if (lowerTick >= upperTick || lowerTick < TickMath.MIN_TICK || upperTick > TickMath.MAX_TICK) {
            revert InvalidTickRange();
        }

        // ensure that some amount of liquidity is provided
        if (amount == 0) revert ZeroLiquidity();

        bool flippedLower = ticks.update(lowerTick, int128(amount), false);
        bool flippedUpper = ticks.update(upperTick, int128(amount), true);

        if (flippedLower) {
            tickBitmap.flipTick(lowerTick, 1);
        }
        if (flippedUpper) {
            tickBitmap.flipTick(upperTick, 1);
        }

        Position.Info storage position = positions.get(owner, lowerTick, upperTick);
        position.update(amount);

        Slot0 memory _slot0 = slot0; // SLOAD for gas optimization

        if (_slot0.tick < lowerTick) {
            amount0 = Math.calcAmount0Delta(
                TickMath.getSqrtRatioAtTick(lowerTick), TickMath.getSqrtRatioAtTick(upperTick), amount
            );
        } else if (_slot0.tick < upperTick) {
            amount0 = Math.calcAmount0Delta(_slot0.sqrtPriceX96, TickMath.getSqrtRatioAtTick(upperTick), amount);
            amount1 = Math.calcAmount1Delta(_slot0.sqrtPriceX96, TickMath.getSqrtRatioAtTick(lowerTick), amount);

            // update the liquidity of the pool, based on the amount being added
            liquidity = LiquidityMath.addLiquidity(liquidity, int128(amount)); // TODO: amount is negative when removing
                // liquidity
        } else {
            amount1 = Math.calcAmount1Delta(
                TickMath.getSqrtRatioAtTick(lowerTick), TickMath.getSqrtRatioAtTick(upperTick), amount
            );
        }

        uint256 balance0Before;
        uint256 balance1Before;

        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();

        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(amount0, amount1, data);

        if (amount0 > 0 && balance0Before + amount0 > balance0()) {
            revert InsufficientInputAmount();
        }

        if (amount1 > 0 && balance1Before + amount1 > balance1()) {
            revert InsufficientInputAmount();
        }

        emit Mint(msg.sender, owner, lowerTick, upperTick, amount, amount0, amount1);
    }

    /// @notice Swaps tokens within the pool.
    /// @dev Executes a swap based on the provided parameters. Emits a Swap event on success.
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
    ) public returns (int256 amount0, int256 amount1) {
        Slot0 memory _slot0 = slot0; // SLOAD for gas optimization
        uint128 _liquidity = liquidity;

        if (
            zeroForOne
                ? sqrtPriceLimitX96 > _slot0.sqrtPriceX96 || sqrtPriceLimitX96 < TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 < _slot0.sqrtPriceX96 || sqrtPriceLimitX96 > TickMath.MAX_SQRT_RATIO
        ) revert InvalidPriceLimit();

        // initialize a SwapState instance
        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: _slot0.sqrtPriceX96,
            tick: _slot0.tick,
            liquidity: _liquidity
        });

        // loop until `amountSpecifiedRemaining` is 0, which will mean that the pool has enough liquidity to buy
        // `amountSpecified` tokens from the user
        while (state.amountSpecifiedRemaining > 0 && state.sqrtPriceX96 != sqrtPriceLimitX96) {
            StepState memory step;

            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            // set up a price range that should provide liquidity for the swap
            (step.nextTick, step.initialized) = tickBitmap.nextInitializedTickWithinOneWord(state.tick, 1, zeroForOne);

            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.nextTick);

            // calculating the amounts that can be provided by the current price range, and the new current price the
            // swap will result in
            (state.sqrtPriceX96, step.amountIn, step.amountOut) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                (zeroForOne ? step.sqrtPriceNextX96 < sqrtPriceLimitX96 : step.sqrtPriceNextX96 > sqrtPriceLimitX96)
                    ? sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                state.liquidity,
                state.amountSpecifiedRemaining
            );

            // updating the SwapState
            state.amountSpecifiedRemaining -= step.amountIn; // the number of tokens the price range can buy from the
                // user
            state.amountCalculated += step.amountOut; // the related number of the other token the pool can sell to the
                // user

            // the swap (recall that trading changes current price)
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    int128 liquidityDelta = ticks.cross(step.nextTick);

                    if (zeroForOne) liquidityDelta = -liquidityDelta;

                    state.liquidity = LiquidityMath.addLiquidity(state.liquidity, liquidityDelta);

                    if (state.liquidity == 0) revert NotEnoughLiquidity();
                }

                state.tick = zeroForOne ? step.nextTick - 1 : step.nextTick;
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        // since this operation writes to the contract’s storage, we want to do it only if the new tick is different,
        // to optimize gas consumption.
        if (state.tick != _slot0.tick) {
            (slot0.sqrtPriceX96, slot0.tick) = (state.sqrtPriceX96, state.tick);
        }

        if (_liquidity != state.liquidity) liquidity = state.liquidity;

        // calculate swap amounts based on the swap direction and the amounts calculated during the swap loop
        (amount0, amount1) = zeroForOne
            ? (int256(amountSpecified - state.amountSpecifiedRemaining), -int256(state.amountCalculated))
            : (-int256(state.amountCalculated), int256(amountSpecified - state.amountSpecifiedRemaining));

        // exchange tokens with the user, depending on the swap direction
        if (zeroForOne) {
            IERC20(token1).transfer(recipient, uint256(-amount1));

            uint256 balance0Before = balance0();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);

            if (balance0Before + uint256(amount0) > balance0()) {
                revert InsufficientInputAmount();
            }
        } else {
            IERC20(token0).transfer(recipient, uint256(-amount0));

            uint256 balance1Before = balance1();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);

            if (balance1Before + uint256(amount1) > balance1()) {
                revert InsufficientInputAmount();
            }
        }

        emit Swap(msg.sender, recipient, amount0, amount1, slot0.sqrtPriceX96, state.liquidity, slot0.tick);
    }

    /// @notice Executes a flash loan for token0 and/or token1.
    /// @dev Transfers the requested token amounts to the caller, then expects the full repayment with any additional fees.
    ///      This function ensures that the pool balance is restored after the flash loan is executed.
    /// @param amount0 The amount of token0 to flash loan to the caller.
    /// @param amount1 The amount of token1 to flash loan to the caller.
    /// @param data Encoded data passed to the callback function for custom logic execution by the caller.
    ///             The callback function must handle repayment of the flash loan with any applicable fees.
    function flash(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) public {
        uint256 balance0Before = IERC20(token0).balanceOf(address(this));
        uint256 balance1Before = IERC20(token1).balanceOf(address(this));

        if (amount0 > 0) IERC20(token0).transfer(msg.sender, amount0);
        if (amount1 > 0) IERC20(token1).transfer(msg.sender, amount1);

        IUniswapV3FlashCallback(msg.sender).uniswapV3FlashCallback(data);

        require(IERC20(token0).balanceOf(address(this)) >= balance0Before);
        require(IERC20(token1).balanceOf(address(this)) >= balance1Before);

        emit Flash(msg.sender, amount0, amount1);
    }

    ////////////////////////////////////////////////////////////////////////////
    //
    // INTERNAL
    //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Fetches the balance of token0 held by the pool.
    /// @return balance The balance of token0.
    function balance0() internal view returns (uint256 balance) {
        balance = IERC20(token0).balanceOf(address(this));
    }

    /// @notice Fetches the balance of token1 held by the pool.
    /// @return balance The balance of token1.
    function balance1() internal view returns (uint256 balance) {
        balance = IERC20(token1).balanceOf(address(this));
    }
}
