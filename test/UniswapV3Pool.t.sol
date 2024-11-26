// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test, stdError } from "forge-std/Test.sol";

import { UniswapV3Pool, IERC20 } from "src/UniswapV3Pool.sol";
import { ERC20Mintable } from "test/mocks/MintableERC20.sol";

contract UniswapV3PoolTest is Test {
    ERC20Mintable token0;
    ERC20Mintable token1;
    UniswapV3Pool pool;

    bool transferInMintCallback = true;
    bool transferInSwapCallback = true;

    struct TestCaseParams {
        uint256 wethBalance;
        uint256 usdcBalance;
        int24 currentTick;
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
        uint160 currentSqrtP;
        bool transferInMintCallback;
        bool transferInSwapCallback;
        bool mintLiquidity;
    }

    function setUp() public {
        token0 = new ERC20Mintable("Ether", "ETH", 18);
        token1 = new ERC20Mintable("USDC", "USDC", 18);
    }

    ////////////////////////
    //      Mint Tests    //
    ////////////////////////

    // test Mint:
    // takes the correct amounts of tokens from us;
    // creates a position with correct key and liquidity;
    // initializes the upper and lower ticks we’ve specified;
    // has correct P and L.
    function test_Mint() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85_176,
            lowerTick: 84_222,
            upperTick: 86_129,
            liquidity: 1_517_882_343_751_509_868_544,
            currentSqrtP: 5_602_277_097_478_614_198_912_276_234_240,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        uint256 expectedAmount0 = 0.998833192822975409 ether;
        uint256 expectedAmount1 = 4999.187247111820044641 ether;

        assertEq(poolBalance0, expectedAmount0, "incorrect token0 deposited amount");
        assertEq(poolBalance1, expectedAmount1, "incorrect token1 deposited amount");

        // We expect specific pre-calculated amounts. And we can also check that these amounts were transferred to the
        // pool:
        assertEq(token0.balanceOf(address(pool)), expectedAmount0);
        assertEq(token1.balanceOf(address(pool)), expectedAmount1);

        bytes32 positionKey = keccak256(abi.encodePacked(address(this), params.lowerTick, params.upperTick));
        uint128 posLiquidity = pool.positions(positionKey);
        assertEq(posLiquidity, params.liquidity);

        (bool tickInitialized, uint128 tickLiquidity) = pool.ticks(params.lowerTick);
        assertTrue(tickInitialized);
        assertEq(tickLiquidity, params.liquidity);

        (tickInitialized, tickLiquidity) = pool.ticks(params.upperTick);
        assertTrue(tickInitialized);
        assertEq(tickLiquidity, params.liquidity);

        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(sqrtPriceX96, 5_602_277_097_478_614_198_912_276_234_240, "invalid current sqrtP");
        assertEq(tick, 85_176, "invalid current tick");
        assertEq(pool.liquidity(), 1_517_882_343_751_509_868_544, "invalid current liquidity");
    }

    function test_Revert_Mint_InsufficientInputAmount() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 0,
            usdcBalance: 0,
            currentTick: 85_176,
            lowerTick: 84_222,
            upperTick: 86_129,
            liquidity: 1_517_882_343_751_509_868_544,
            currentSqrtP: 5_602_277_097_478_614_198_912_276_234_240,
            transferInMintCallback: false,
            transferInSwapCallback: false,
            mintLiquidity: false
        });
        setupTestCase(params);

        vm.expectRevert(UniswapV3Pool.InsufficientInputAmount.selector);
        pool.mint(address(this), params.lowerTick, params.upperTick, params.liquidity, "");
    }

    function test_Revert_Mint_ZeroLiquidity() public {
        pool = new UniswapV3Pool(address(token0), address(token1), uint160(1), 0);
        vm.expectRevert(UniswapV3Pool.ZeroLiquidity.selector);
        pool.mint(address(this), 0, 1, 0, "");
    }

    function test_Revert_Mint_InvalidTickRange() public {
        pool = new UniswapV3Pool(address(token0), address(token1), uint160(1), 0);
        vm.expectRevert(UniswapV3Pool.InvalidTickRange.selector);
        pool.mint(address(this), -887_273, 0, 0, "");

        vm.expectRevert(UniswapV3Pool.InvalidTickRange.selector);
        pool.mint(address(this), 0, 887_273, 0, "");
    }

    ////////////////////////
    //     Swap Tests     //
    ////////////////////////

    function test_Swap_BuyEth() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85_176,
            lowerTick: 84_222,
            upperTick: 86_129,
            liquidity: 1_517_882_343_751_509_868_544,
            currentSqrtP: 5_602_277_097_478_614_198_912_276_234_240,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        uint256 swapAmount = 42 ether; // 42 usdc
        token1.mint(address(this), swapAmount);
        token1.approve(address(this), swapAmount);

        UniswapV3Pool.CallbackData memory extra =
            UniswapV3Pool.CallbackData({ token0: address(token0), token1: address(token1), payer: address(this) });

        int256 userBalance0Before = int256(token0.balanceOf(address(this)));
        int256 userBalance1Before = int256(token1.balanceOf(address(this)));

        (int256 amount0Delta, int256 amount1Delta) = pool.swap(address(this), false, swapAmount, abi.encode(extra));

        assertEq(amount0Delta, -0.008396714242162445 ether, "invalid ETH out");
        assertEq(amount1Delta, 42 ether, "invalid USDC in");

        assertEq(
            token0.balanceOf(address(this)), uint256(userBalance0Before - amount0Delta), "invalid user ETH balance"
        );
        assertEq(
            token1.balanceOf(address(this)), uint256(userBalance1Before - amount1Delta), "invalid user USDC balance"
        );

        assertEq(
            token0.balanceOf(address(pool)), uint256(int256(poolBalance0) + amount0Delta), "invalid pool ETH balance"
        );
        assertEq(
            token1.balanceOf(address(pool)), uint256(int256(poolBalance1) + amount1Delta), "invalid pool USDC balance"
        );

        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(sqrtPriceX96, 5_604_469_350_942_327_889_444_743_441_197, "invalid current sqrtP");
        assertEq(tick, 85_184, "invalid current tick");
        assertEq(pool.liquidity(), 1_517_882_343_751_509_868_544, "invalid current liquidity");
    }

    function test_Revert_Swap_BuyEth_InsufficientInputAmount() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85_176,
            lowerTick: 84_222,
            upperTick: 86_129,
            liquidity: 1_517_882_343_751_509_868_544,
            currentSqrtP: 5_602_277_097_478_614_198_912_276_234_240,
            transferInMintCallback: true,
            transferInSwapCallback: false,
            mintLiquidity: true
        });
        setupTestCase(params);
        vm.expectRevert(UniswapV3Pool.InsufficientInputAmount.selector);
        pool.swap(address(this), false, 42 ether, "");
    }

    function test_Swap_BuyUSDC() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85_176,
            lowerTick: 84_222,
            upperTick: 86_129,
            liquidity: 1_517_882_343_751_509_868_544,
            currentSqrtP: 5_602_277_097_478_614_198_912_276_234_240,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        uint256 swapAmount = 0.01337 ether;
        token0.mint(address(this), swapAmount);
        token0.approve(address(this), swapAmount);

        bytes memory extra = encodeExtra(address(token0), address(token1), address(this));

        int256 userBalance0Before = int256(token0.balanceOf(address(this)));
        int256 userBalance1Before = int256(token1.balanceOf(address(this)));

        (int256 amount0Delta, int256 amount1Delta) = pool.swap(address(this), true, swapAmount, extra);

        assertEq(amount0Delta, 0.01337 ether, "invalid ETH in");
        assertEq(amount1Delta, -66.808388890199406685 ether, "invalid USDC out");

        assertEq(
            token0.balanceOf(address(this)), uint256(userBalance0Before - amount0Delta), "invalid user ETH balance"
        );
        assertEq(
            token1.balanceOf(address(this)), uint256(userBalance1Before - amount1Delta), "invalid user USDC balance"
        );

        assertEq(
            token0.balanceOf(address(pool)), uint256(int256(poolBalance0) + amount0Delta), "invalid pool ETH balance"
        );
        assertEq(
            token1.balanceOf(address(pool)), uint256(int256(poolBalance1) + amount1Delta), "invalid pool USDC balance"
        );

        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(sqrtPriceX96, 5_598_789_932_670_288_701_514_545_755_210, "invalid current sqrtP");
        assertEq(tick, 85_163, "invalid current tick");
        assertEq(pool.liquidity(), 1_517_882_343_751_509_868_544, "invalid current liquidity");
    }

    function test_Swap_Mixed() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85_176,
            lowerTick: 84_222,
            upperTick: 86_129,
            liquidity: 1_517_882_343_751_509_868_544,
            currentSqrtP: 5_602_277_097_478_614_198_912_276_234_240,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        uint256 ethAmount = 0.01337 ether;
        token0.mint(address(this), ethAmount);
        token0.approve(address(this), ethAmount);

        uint256 usdcAmount = 55 ether;
        token1.mint(address(this), usdcAmount);
        token1.approve(address(this), usdcAmount);

        bytes memory extra = encodeExtra(address(token0), address(token1), address(this));

        int256 userBalance0Before = int256(token0.balanceOf(address(this)));
        int256 userBalance1Before = int256(token1.balanceOf(address(this)));

        (int256 amount0Delta1, int256 amount1Delta1) = pool.swap(address(this), true, ethAmount, extra);

        (int256 amount0Delta2, int256 amount1Delta2) = pool.swap(address(this), false, usdcAmount, extra);

        assertEq(
            token0.balanceOf(address(this)),
            uint256(userBalance0Before - amount0Delta1 - amount0Delta2),
            "invalid user ETH balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            uint256(userBalance1Before - amount1Delta1 - amount1Delta2),
            "invalid user USDC balance"
        );

        assertEq(
            token0.balanceOf(address(pool)),
            uint256(int256(poolBalance0) + amount0Delta1 + amount0Delta2),
            "invalid pool ETH balance"
        );
        assertEq(
            token1.balanceOf(address(pool)),
            uint256(int256(poolBalance1) + amount1Delta1 + amount1Delta2),
            "invalid pool USDC balance"
        );

        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(sqrtPriceX96, 5_601_660_740_777_532_820_068_967_097_654, "invalid current sqrtP");
        assertEq(tick, 85_173, "invalid current tick");
        assertEq(pool.liquidity(), 1_517_882_343_751_509_868_544, "invalid current liquidity");
    }

    function test_Revert_Swap_BuyEth_NotEnoughLiquidity() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85_176,
            lowerTick: 84_222,
            upperTick: 86_129,
            liquidity: 1_517_882_343_751_509_868_544,
            currentSqrtP: 5_602_277_097_478_614_198_912_276_234_240,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        setupTestCase(params);

        uint256 ethAmount = 1.1 ether;
        token0.mint(address(this), ethAmount);
        token0.approve(address(this), ethAmount);

        bytes memory extra = encodeExtra(address(token0), address(token1), address(this));

        vm.expectRevert(stdError.arithmeticError);
        pool.swap(address(this), true, ethAmount, extra);
    }

    function test_Revert_Swap_BuyUSDC_NotEnoughLiquidity() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85_176,
            lowerTick: 84_222,
            upperTick: 86_129,
            liquidity: 1_517_882_343_751_509_868_544,
            currentSqrtP: 5_602_277_097_478_614_198_912_276_234_240,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        setupTestCase(params);

        uint256 usdcAmount = 5200 ether;
        token1.mint(address(this), usdcAmount);
        token1.approve(address(this), usdcAmount);

        bytes memory extra = encodeExtra(address(token0), address(token1), address(this));

        vm.expectRevert(stdError.arithmeticError);
        pool.swap(address(this), true, usdcAmount, extra);
    }

    ////////////////////////
    //   Public Helpers   //
    ////////////////////////

    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata data) public {
        if (transferInMintCallback) {
            UniswapV3Pool.CallbackData memory extra = abi.decode(data, (UniswapV3Pool.CallbackData));
            IERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0);
            IERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1);
        }
    }

    function uniswapV3SwapCallback(int256 amount0, int256 amount1, bytes calldata data) public {
        if (transferInSwapCallback) {
            UniswapV3Pool.CallbackData memory extra = abi.decode(data, (UniswapV3Pool.CallbackData));

            if (amount0 > 0) {
                IERC20(extra.token0).transferFrom(extra.payer, msg.sender, uint256(amount0));
            }

            if (amount1 > 0) {
                IERC20(extra.token1).transferFrom(extra.payer, msg.sender, uint256(amount1));
            }
        }
    }

    ////////////////////////
    //  Internal Helpers  //
    ////////////////////////

    function setupTestCase(TestCaseParams memory params)
        internal
        returns (uint256 poolBalance0, uint256 poolBalance1)
    {
        token0.mint(address(this), params.wethBalance);
        token1.mint(address(this), params.usdcBalance);

        pool = new UniswapV3Pool(address(token0), address(token1), params.currentSqrtP, params.currentTick);

        if (params.mintLiquidity) {
            token0.approve(address(this), params.wethBalance);
            token1.approve(address(this), params.usdcBalance);

            bytes memory extra = encodeExtra(address(token0), address(token1), address(this));

            (poolBalance0, poolBalance1) =
                pool.mint(address(this), params.lowerTick, params.upperTick, params.liquidity, extra);
        }

        transferInMintCallback = params.transferInMintCallback;
        transferInSwapCallback = params.transferInSwapCallback;
    }

    function encodeExtra(address token0, address token1, address payer) internal pure returns (bytes memory) {
        return abi.encode(UniswapV3Pool.CallbackData({ token0: token0, token1: token1, payer: payer }));
    }
}
