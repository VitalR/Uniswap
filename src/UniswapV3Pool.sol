// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "prb-math/Common.sol";
import { IERC20 } from "@openzeppelin/token/ERC20/IERC20.sol";

import { IUniswapV3FlashCallback } from "./interfaces/IUniswapV3FlashCallback.sol";
import { IUniswapV3MintCallback } from "./interfaces/IUniswapV3MintCallback.sol";
import { IUniswapV3Pool } from "./interfaces/IUniswapV3Pool.sol";
import { IUniswapV3PoolDeployer } from "./interfaces/IUniswapV3PoolDeployer.sol";
import { IUniswapV3SwapCallback } from "./interfaces/IUniswapV3SwapCallback.sol";

import { FixedPoint128 } from "./libraries/FixedPoint128.sol";
import { LiquidityMath } from "./libraries/LiquidityMath.sol";
import { Math } from "./libraries/Math.sol";
import { Oracle } from "./libraries/Oracle.sol";
import { Position } from "./libraries/Position.sol";
import { SwapMath } from "./libraries/SwapMath.sol";
import { Tick } from "./libraries/Tick.sol";
import { TickMath } from "./libraries/TickMath.sol";
import { TickBitmap } from "./libraries/TickBitmap.sol";

/// @title UniswapV3Pool
/// @notice A Uniswap V3 pool contract that facilitates token swaps and liquidity provision with concentrated liquidity.
/// @dev This contract implements the core functionalities of a Uniswap V3 pool, including minting liquidity positions,
/// executing token swaps within defined price ranges, and managing ticks and liquidity for efficient market making.
contract UniswapV3Pool is IUniswapV3Pool {
    using Oracle for Oracle.Observation[65_535];
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    ////////////////////////////////////////////////////////////////////////////
    //
    // CONFIGURATION & STORAGE
    //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice The address of the factory that deployed this pool.
    address public immutable factory;
    /// @notice Address of the first token in the pool.
    address public immutable token0;
    /// @notice Address of the second token in the pool.
    address public immutable token1;
    /// @notice The tick spacing for this pool.
    uint24 public immutable tickSpacing;
    /// @notice The fee tier for this pool, expressed in hundredths of a bip (e.g., 500 = 0.05%).
    uint24 public immutable fee;
    /// @notice The global cumulative fee growth for token0, scaled by 2^128.
    uint256 public feeGrowthGlobal0X128;
    /// @notice The global cumulative fee growth for token1, scaled by 2^128.
    uint256 public feeGrowthGlobal1X128;

    // First slot will contain essential data. Packing variables that are read together.
    struct Slot0 {
        /// @notice The current price of the pool in sqrt(P) format.
        uint160 sqrtPriceX96;
        /// @notice The current tick of the pool.
        int24 tick;
        // Most recent observation index
        uint16 observationIndex;
        // Maximum number of observations
        uint16 observationCardinality;
        // Next maximum number of observations
        uint16 observationCardinalityNext;
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
        /// @notice The cumulative fee growth during the swap, scaled by 2^128.
        uint256 feeGrowthGlobalX128;
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
        /// @notice The fee amount incurred during the current swap step.
        uint256 feeAmount;
    }

    /// @notice The current liquidity of the pool.
    uint128 public liquidity;

    /// @notice Stores tick information mapped by tick indexes.
    mapping(int24 => Tick.Info) public ticks;
    /// @notice Bitmap representing initialized tick states.
    mapping(int16 => uint256) public tickBitmap;
    /// @notice Stores position information mapped by position hashes.
    mapping(bytes32 => Position.Info) public positions;

    Oracle.Observation[65_535] public observations;

    ////////////////////////////////////////////////////////////////////////////
    //
    // CONSTRUCTOR & FUNCTIONS
    //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Constructor initializes the pool parameters from the deployer.
    constructor() {
        (factory, token0, token1, tickSpacing, fee) = IUniswapV3PoolDeployer(msg.sender).parameters();
    }

    /// @notice Initializes the pool with a specific sqrt price.
    /// @dev Ensures the pool is only initialized once.
    /// @param _sqrtPriceX96 The initial sqrt price of the pool.
    function initialize(uint160 _sqrtPriceX96) public {
        if (slot0.sqrtPriceX96 != 0) revert AlreadyInitialized();

        int24 _tick = TickMath.getTickAtSqrtRatio(_sqrtPriceX96);

        (uint16 cardinality, uint16 cardinalityNext) = observations.initialize(_blockTimestamp());

        slot0 = Slot0({
            sqrtPriceX96: _sqrtPriceX96,
            tick: _tick,
            observationIndex: 0,
            observationCardinality: cardinality,
            observationCardinalityNext: cardinalityNext
        });
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

        (, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: owner,
                lowerTick: lowerTick,
                upperTick: upperTick,
                liquidityDelta: int128(amount)
            })
        );

        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

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

    /// @notice Burns liquidity from a position and accounts for the owed tokens.
    /// @dev Reduces the liquidity of a position and updates the tokens owed. Emits a `Burn` event.
    /// @param lowerTick The lower tick of the position from which liquidity is being burned.
    /// @param upperTick The upper tick of the position from which liquidity is being burned.
    /// @param amount The amount of liquidity to burn.
    /// @return amount0 The amount of token0 accounted for burning the liquidity.
    /// @return amount1 The amount of token1 accounted for burning the liquidity.
    function burn(int24 lowerTick, int24 upperTick, uint128 amount) public returns (uint256 amount0, uint256 amount1) {
        (Position.Info storage position, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: msg.sender,
                lowerTick: lowerTick,
                upperTick: upperTick,
                liquidityDelta: -(int128(amount))
            })
        );

        amount0 = uint256(-amount0Int);
        amount1 = uint256(-amount1Int);

        if (amount0 > 0 || amount1 > 0) {
            (position.tokensOwed0, position.tokensOwed1) =
                (position.tokensOwed0 + uint128(amount0), position.tokensOwed1 + uint128(amount1));
        }

        emit Burn(msg.sender, lowerTick, upperTick, amount, amount0, amount1);
    }

    /// @notice Collects owed tokens from a position.
    /// @dev Transfers the owed tokens (up to the requested amounts) to the recipient. Emits a `Collect` event.
    /// @param recipient The address receiving the collected tokens.
    /// @param lowerTick The lower tick of the position from which tokens are being collected.
    /// @param upperTick The upper tick of the position from which tokens are being collected.
    /// @param amount0Requested The maximum amount of token0 to collect.
    /// @param amount1Requested The maximum amount of token1 to collect.
    /// @return amount0 The actual amount of token0 collected.
    /// @return amount1 The actual amount of token1 collected.
    function collect(
        address recipient,
        int24 lowerTick,
        int24 upperTick,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) public returns (uint128 amount0, uint128 amount1) {
        Position.Info storage position = positions.get(msg.sender, lowerTick, upperTick);

        amount0 = amount0Requested > position.tokensOwed0 ? position.tokensOwed0 : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1 ? position.tokensOwed1 : amount1Requested;

        if (amount0 > 0) {
            position.tokensOwed0 -= amount0;
            IERC20(token0).transfer(recipient, amount0);
        }

        if (amount1 > 0) {
            position.tokensOwed1 -= amount1;
            IERC20(token1).transfer(recipient, amount1);
        }

        emit Collect(msg.sender, recipient, lowerTick, upperTick, amount0, amount1);
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
            feeGrowthGlobalX128: zeroForOne ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128,
            liquidity: _liquidity
        });

        // loop until `amountSpecifiedRemaining` is 0, which will mean that the pool has enough liquidity to buy
        // `amountSpecified` tokens from the user
        while (state.amountSpecifiedRemaining > 0 && state.sqrtPriceX96 != sqrtPriceLimitX96) {
            StepState memory step;

            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            // set up a price range that should provide liquidity for the swap
            (step.nextTick, step.initialized) =
                tickBitmap.nextInitializedTickWithinOneWord(state.tick, int24(tickSpacing), zeroForOne);

            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.nextTick);

            // calculating the amounts that can be provided by the current price range, and the new current price the
            // swap will result in
            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                (zeroForOne ? step.sqrtPriceNextX96 < sqrtPriceLimitX96 : step.sqrtPriceNextX96 > sqrtPriceLimitX96)
                    ? sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                state.liquidity,
                state.amountSpecifiedRemaining,
                fee
            );

            state.amountSpecifiedRemaining -= step.amountIn + step.feeAmount;
            state.amountCalculated += step.amountOut;

            if (state.liquidity > 0) {
                state.feeGrowthGlobalX128 += mulDiv(step.feeAmount, FixedPoint128.Q128, state.liquidity);
            }

            // the swap (recall that trading changes current price)
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    int128 liquidityDelta = ticks.cross(
                        step.nextTick,
                        (zeroForOne ? state.feeGrowthGlobalX128 : feeGrowthGlobal0X128),
                        (zeroForOne ? feeGrowthGlobal1X128 : state.feeGrowthGlobalX128)
                    );

                    if (zeroForOne) liquidityDelta = -liquidityDelta;

                    state.liquidity = LiquidityMath.addLiquidity(state.liquidity, liquidityDelta);

                    if (state.liquidity == 0) revert NotEnoughLiquidity();
                }

                state.tick = zeroForOne ? step.nextTick - 1 : step.nextTick;
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        //
        if (state.tick != _slot0.tick) {
            (uint16 observationIndex, uint16 observationCardinality) = observations.write(
                _slot0.observationIndex,
                _blockTimestamp(),
                _slot0.tick,
                _slot0.observationCardinality,
                _slot0.observationCardinalityNext
            );

            (slot0.sqrtPriceX96, slot0.tick, slot0.observationIndex, slot0.observationCardinality) =
                (state.sqrtPriceX96, state.tick, observationIndex, observationCardinality);
        } else {
            slot0.sqrtPriceX96 = state.sqrtPriceX96;
        }

        if (_liquidity != state.liquidity) liquidity = state.liquidity;

        if (zeroForOne) {
            feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
        } else {
            feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
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

        emit Swap(msg.sender, recipient, amount0, amount1, slot0.sqrtPriceX96, state.liquidity, slot0.tick);
    }

    /// @notice Executes a flash loan for token0 and/or token1.
    /// @dev Transfers the requested token amounts to the caller, then expects the full repayment with any additional
    /// fees. This function ensures that the pool balance is restored after the flash loan is executed.
    /// @param amount0 The amount of token0 to flash loan to the caller.
    /// @param amount1 The amount of token1 to flash loan to the caller.
    /// @param data Encoded data passed to the callback function for custom logic execution by the caller.
    /// The callback function must handle repayment of the flash loan with any applicable fees.
    function flash(uint256 amount0, uint256 amount1, bytes calldata data) public {
        uint256 fee0 = Math.mulDivRoundingUp(amount0, fee, 1e6);
        uint256 fee1 = Math.mulDivRoundingUp(amount1, fee, 1e6);

        uint256 balance0Before = IERC20(token0).balanceOf(address(this));
        uint256 balance1Before = IERC20(token1).balanceOf(address(this));

        if (amount0 > 0) IERC20(token0).transfer(msg.sender, amount0);
        if (amount1 > 0) IERC20(token1).transfer(msg.sender, amount1);

        IUniswapV3FlashCallback(msg.sender).uniswapV3FlashCallback(fee0, fee1, data);

        if (IERC20(token0).balanceOf(address(this)) < balance0Before + fee0) {
            revert FlashLoanNotPaid();
        }
        if (IERC20(token1).balanceOf(address(this)) < balance1Before + fee1) {
            revert FlashLoanNotPaid();
        }

        emit Flash(msg.sender, amount0, amount1);
    }

    function observe(uint32[] calldata secondsAgos) public view returns (int56[] memory tickCumulatives) {
        return observations.observe(
            _blockTimestamp(), secondsAgos, slot0.tick, slot0.observationIndex, slot0.observationCardinality
        );
    }

    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) public {
        uint16 observationCardinalityNextOld = slot0.observationCardinalityNext;
        uint16 observationCardinalityNextNew =
            observations.grow(observationCardinalityNextOld, observationCardinalityNext);

        if (observationCardinalityNextNew != observationCardinalityNextOld) {
            slot0.observationCardinalityNext = observationCardinalityNextNew;
            emit IncreaseObservationCardinalityNext(observationCardinalityNextOld, observationCardinalityNextNew);
        }
    }

    ////////////////////////////////////////////////////////////////////////////
    //
    // INTERNAL
    //
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Modifies the liquidity of a position by adding or removing liquidity.
    /// @dev This function updates the position and associated ticks based on the liquidity delta.
    ///      It also updates the fee growth and calculates the amount of tokens owed.
    /// @param params The parameters for modifying the position, encapsulated in `ModifyPositionParams`.
    /// @return position The updated position information.
    /// @return amount0 The amount of token0 owed due to the liquidity change.
    /// @return amount1 The amount of token1 owed due to the liquidity change.
    function _modifyPosition(ModifyPositionParams memory params)
        internal
        returns (Position.Info storage position, int256 amount0, int256 amount1)
    {
        // Gas optimizations: Load frequently used values into memory.
        Slot0 memory _slot0 = slot0;
        uint256 feeGrowthGlobal0X128_ = feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128_ = feeGrowthGlobal1X128;

        // Retrieve the position for the given owner and tick range.
        position = positions.get(params.owner, params.lowerTick, params.upperTick);

        // Update the lower and upper ticks with the liquidity change.
        bool flippedLower = ticks.update(
            params.lowerTick,
            _slot0.tick,
            int128(params.liquidityDelta),
            feeGrowthGlobal0X128_,
            feeGrowthGlobal1X128_,
            false
        );
        bool flippedUpper = ticks.update(
            params.upperTick,
            _slot0.tick,
            int128(params.liquidityDelta),
            feeGrowthGlobal0X128_,
            feeGrowthGlobal1X128_,
            true
        );

        // If a tick was uninitialized and is now initialized, flip its bitmap.
        if (flippedLower) {
            tickBitmap.flipTick(params.lowerTick, int24(tickSpacing));
        }
        if (flippedUpper) {
            tickBitmap.flipTick(params.upperTick, int24(tickSpacing));
        }

        // Calculate fee growth inside the tick range.
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = ticks.getFeeGrowthInside(
            params.lowerTick, params.upperTick, _slot0.tick, feeGrowthGlobal0X128_, feeGrowthGlobal1X128_
        );

        // Update the position with the calculated fee growth and liquidity change.
        position.update(params.liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128);

        // Calculate the token amounts owed based on the current and target ticks.
        if (_slot0.tick < params.lowerTick) {
            amount0 = Math.calcAmount0Delta(
                TickMath.getSqrtRatioAtTick(params.lowerTick),
                TickMath.getSqrtRatioAtTick(params.upperTick),
                params.liquidityDelta
            );
        } else if (_slot0.tick < params.upperTick) {
            amount0 = Math.calcAmount0Delta(
                _slot0.sqrtPriceX96, TickMath.getSqrtRatioAtTick(params.upperTick), params.liquidityDelta
            );

            amount1 = Math.calcAmount1Delta(
                TickMath.getSqrtRatioAtTick(params.lowerTick), _slot0.sqrtPriceX96, params.liquidityDelta
            );

            liquidity = LiquidityMath.addLiquidity(liquidity, params.liquidityDelta);
        } else {
            amount1 = Math.calcAmount1Delta(
                TickMath.getSqrtRatioAtTick(params.lowerTick),
                TickMath.getSqrtRatioAtTick(params.upperTick),
                params.liquidityDelta
            );
        }
    }

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

    function _blockTimestamp() internal view returns (uint32 timestamp) {
        timestamp = uint32(block.timestamp);
    }
}
