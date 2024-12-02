// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IERC20 } from "./interfaces/IERC20.sol";
import { IUniswapV3Pool } from "./interfaces/IUniswapV3Pool.sol";
import { IUniswapV3MintCallback } from "./interfaces/IUniswapV3MintCallback.sol";
import { IUniswapV3SwapCallback } from "./interfaces/IUniswapV3SwapCallback.sol";

import { LiquidityMath } from "./libraries/LiquidityMath.sol";
import { Math } from "./libraries/Math.sol";
import { SwapMath } from "./libraries/SwapMath.sol";
import { Position } from "./libraries/Position.sol";
import { Tick } from "./libraries/Tick.sol";
import { TickMath } from "./libraries/TickMath.sol";
import { TickBitmap } from "./libraries/TickBitmap.sol";

contract UniswapV3Pool is IUniswapV3Pool {
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    error InsufficientInputAmount();
    error InvalidTickRange();
    error ZeroLiquidity();

    // Pool tokens, immutable
    address public immutable token0;
    address public immutable token1;

    // First slot will contain essencian data. Packing variables that are read together
    struct Slot0 {
        // the current price - sqrt(P)
        // 20 bytes
        uint160 sqrtPriceX96;
        // the current tick
        // 3 bytes
        int24 tick;
    }

    Slot0 public slot0;

    // SwapState maintains the current swap’s state
    struct SwapState {
        uint256 amountSpecifiedRemaining; // the remaining amount of tokens that need to be bought by the pool
        uint256 amountCalculated; // the out amount calculated by the contract
        uint160 sqrtPriceX96; // the new current price
        int24 tick; // the tick after a swap is done
        uint128 liquidity;
    }

    // StepState maintains the current swap step’s state
    // This structure tracks the state of one iteration of an “order filling”.
    struct StepState {
        uint160 sqrtPriceStartX96; // tracks the price the iteration begins with
        int24 nextTick; // the next initialized tick that will provide liquidity for the swap
        bool initialized;
        uint160 sqrtPriceNextX96; // the price at the next tick
        uint256 amountIn; // amount that can be provided by the liquidity of the current iteration
        uint256 amountOut; // amount that can be provided by the liquidity of the current iteration
    }

    // Amount of liquidity, L.
    uint128 public liquidity;

    // Tick info
    mapping(int24 => Tick.Info) public ticks;
    // The tick index is stored in a state variable
    mapping(int16 => uint256) public tickBitmap;
    // Position info
    mapping(bytes32 => Position.Info) public positions;

    event Mint(
        address sender,
        address owner,
        int24 lowerTick,
        int24 upperTick,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    event Swap(
        address sender,
        address recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    constructor(address _token0, address _token1, uint160 _sqrtPriceX96, int24 _tick) {
        token0 = _token0;
        token1 = _token1;

        slot0 = Slot0({ sqrtPriceX96: _sqrtPriceX96, tick: _tick });
    }

    //////////////////////////
    //  External Functions  //
    //////////////////////////

    /// @param owner owner’s address, to track the owner of the liquidity
    /// @param lowerTick lower ticks, to set the bounds of a price range
    /// @param upperTick upper ticks, to set the bounds of a price range
    /// @param amount of liquidity the user want to provide
    /// @param data encoded data for the callbacks
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

    /// @param recipient the address of a receiver of tokens
    /// @param zeroForOne is the flag that controls swap direction: when true, token0 is traded in for token1; 
    /// when false, it’s the opposite.
    /// For example, if token0 is ETH and token1 is USDC, setting zeroForOne to true means buying USDC for ETH.
    /// @param amountSpecified is the number of tokens the user wants to sell.
    /// @param sqrtPriceLimitX96 sqrtPriceLimitX96
    /// @param data encoded data for the callbacks.
    function swap(
        address recipient,
        bool zeroForOne,
        uint256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) public returns (int256 amount0, int256 amount1) {
        Slot0 memory _slot0 = slot0; // SLOAD for gas optimization
        uint128 _liquidity = liquidity;

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
                liquidity,
                state.amountSpecifiedRemaining
            );

            // updating the SwapState
            state.amountSpecifiedRemaining -= step.amountIn; // the number of tokens the price range can buy from the
                // user
            state.amountCalculated += step.amountOut; // the related number of the other token the pool can sell to the
                // user
            state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96); // the current price that will be set after
                // the swap (recall that trading changes current price)
        }

        // since this operation writes to the contract’s storage, we want to do it only if the new tick is different,
        // to optimize gas consumption.
        if (state.tick != _slot0.tick) {
            (slot0.sqrtPriceX96, slot0.tick) = (state.sqrtPriceX96, state.tick);
        }

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

        emit Swap(msg.sender, recipient, amount0, amount1, slot0.sqrtPriceX96, liquidity, slot0.tick);
    }

    //////////////////////////
    //  Internal Functions  //
    //////////////////////////

    function balance0() internal returns (uint256 balance) {
        balance = IERC20(token0).balanceOf(address(this));
    }

    function balance1() internal returns (uint256 balance) {
        balance = IERC20(token1).balanceOf(address(this));
    }
}
