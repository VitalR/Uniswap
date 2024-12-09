// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test, stdError } from "forge-std/Test.sol";

import { UniswapV3Pool, IUniswapV3Pool, IERC20 } from "src/UniswapV3Pool.sol";
import { UniswapV3Factory } from "src/UniswapV3Factory.sol";
import { UniswapV3PoolUtils } from "test/utils/UniswapV3Pool.Utils.t.sol";
import { ERC20Mock } from "test/mocks/ERC20Mock.sol";

import "lib/forge-std/src/console2.sol";

contract UniswapV3PoolTest is Test, UniswapV3PoolUtils {
    ERC20Mock weth;
    ERC20Mock usdc;
    UniswapV3Pool pool;
    UniswapV3Factory factory;

    bool transferInMintCallback = true;
    bool flashCallbackCalled = false;

    function setUp() public {
        usdc = new ERC20Mock("USDC", "USDC");
        weth = new ERC20Mock("Wrapped Ether", "WETH");
        factory = new UniswapV3Factory();
    }

    function testInitialize() public {
        pool = UniswapV3Pool(factory.createPool(address(weth), address(usdc), 60));

        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(sqrtPriceX96, 0, "invalid sqrtPriceX96");
        assertEq(tick, 0, "invalid tick");

        pool.initialize(sqrtP(31_337));

        (sqrtPriceX96, tick) = pool.slot0();
        assertEq(sqrtPriceX96, 14_025_175_117_687_921_942_002_399_182_848, "invalid sqrtPriceX96");
        assertEq(tick, 103_530, "invalid tick");

        vm.expectRevert(encodeError("AlreadyInitialized()"));
        pool.initialize(sqrtP(42));
    }

    function testMintInRange() public {
        LiquidityRange[] memory liquidity = new LiquidityRange[](1);
        liquidity[0] = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentPrice: 5000,
            liquidity: liquidity,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiqudity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        (uint256 expectedAmount0, uint256 expectedAmount1) = (0.987078348444137445 ether, 5000 ether);

        assertEq(poolBalance0, expectedAmount0, "incorrect weth deposited amount");
        assertEq(poolBalance1, expectedAmount1, "incorrect usdc deposited amount");

        assertMintState(
            ExpectedStateAfterMint({
                pool: pool,
                token0: weth,
                token1: usdc,
                amount0: expectedAmount0,
                amount1: expectedAmount1,
                lowerTick: liquidity[0].lowerTick,
                upperTick: liquidity[0].upperTick,
                positionLiquidity: liquidity[0].amount,
                currentLiquidity: liquidity[0].amount,
                sqrtPriceX96: sqrtP(5000),
                tick: tick(5000)
            })
        );
    }

    function testMintRangeBelow() public {
        LiquidityRange[] memory liquidity = new LiquidityRange[](1);
        liquidity[0] = liquidityRange(4000, 4996, 1 ether, 5000 ether, 5000);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentPrice: 5000,
            liquidity: liquidity,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiqudity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        (uint256 expectedAmount0, uint256 expectedAmount1) = (0 ether, 4999.999999999999999994 ether);

        assertEq(poolBalance0, expectedAmount0, "incorrect weth deposited amount");
        assertEq(poolBalance1, expectedAmount1, "incorrect usdc deposited amount");

        assertMintState(
            ExpectedStateAfterMint({
                pool: pool,
                token0: weth,
                token1: usdc,
                amount0: expectedAmount0,
                amount1: expectedAmount1,
                lowerTick: liquidity[0].lowerTick,
                upperTick: liquidity[0].upperTick,
                positionLiquidity: liquidity[0].amount,
                currentLiquidity: 0,
                sqrtPriceX96: sqrtP(5000),
                tick: tick(5000)
            })
        );
    }

    function testMintRangeAbove() public {
        LiquidityRange[] memory liquidity = new LiquidityRange[](1);
        liquidity[0] = liquidityRange(5001, 6250, 1 ether, 5000 ether, 5000);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 10 ether,
            usdcBalance: 5000 ether,
            currentPrice: 5000,
            liquidity: liquidity,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiqudity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        (uint256 expectedAmount0, uint256 expectedAmount1) = (1 ether, 0);

        assertEq(poolBalance0, expectedAmount0, "incorrect weth deposited amount");
        assertEq(poolBalance1, expectedAmount1, "incorrect usdc deposited amount");

        assertMintState(
            ExpectedStateAfterMint({
                pool: pool,
                token0: weth,
                token1: usdc,
                amount0: expectedAmount0,
                amount1: expectedAmount1,
                lowerTick: liquidity[0].lowerTick,
                upperTick: liquidity[0].upperTick,
                positionLiquidity: liquidity[0].amount,
                currentLiquidity: 0,
                sqrtPriceX96: sqrtP(5000),
                tick: tick(5000)
            })
        );
    }

    //
    //          5000
    //   4545 ----|---- 5500
    // 4000 ------|------ 6250
    //
    function testMintOverlappingRanges() public {
        LiquidityRange[] memory liquidity = new LiquidityRange[](2);
        liquidity[0] = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);
        liquidity[1] = liquidityRange(4000, 6250, (liquidity[0].amount * 75) / 100);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 3 ether,
            usdcBalance: 15_000 ether,
            currentPrice: 5000,
            liquidity: liquidity,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiqudity: true
        });
        setupTestCase(params);

        (uint256 amount0, uint256 amount1) = (2.72758041550084872 ether, 13_747.87182311273329981 ether);

        assertMintState(
            ExpectedStateAfterMint({
                pool: pool,
                token0: weth,
                token1: usdc,
                amount0: amount0,
                amount1: amount1,
                lowerTick: tick60(4545),
                upperTick: tick60(5500),
                positionLiquidity: liquidity[0].amount,
                currentLiquidity: liquidity[0].amount + liquidity[1].amount,
                sqrtPriceX96: sqrtP(5000),
                tick: tick(5000)
            })
        );
        assertMintState(
            ExpectedStateAfterMint({
                pool: pool,
                token0: weth,
                token1: usdc,
                amount0: amount0,
                amount1: amount1,
                lowerTick: tick60(4000),
                upperTick: tick60(6250),
                positionLiquidity: liquidity[1].amount,
                currentLiquidity: liquidity[0].amount + liquidity[1].amount,
                sqrtPriceX96: sqrtP(5000),
                tick: tick(5000)
            })
        );
    }

    function testMintInvalidTickRangeLower() public {
        pool = deployPool(factory, address(weth), address(usdc), 60, 1);

        vm.expectRevert(encodeError("InvalidTickRange()"));
        pool.mint(address(this), -887_273, 0, 0, "");
    }

    function testMintInvalidTickRangeUpper() public {
        pool = deployPool(factory, address(weth), address(usdc), 60, 1);

        vm.expectRevert(encodeError("InvalidTickRange()"));
        pool.mint(address(this), 0, 887_273, 0, "");
    }

    function testMintZeroLiquidity() public {
        pool = deployPool(factory, address(weth), address(usdc), 60, 1);

        vm.expectRevert(encodeError("ZeroLiquidity()"));
        pool.mint(address(this), 0, 1, 0, "");
    }

    function testMintInsufficientTokenBalance() public {
        LiquidityRange[] memory liquidity = new LiquidityRange[](1);
        liquidity[0] = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 0,
            usdcBalance: 0,
            currentPrice: 5000,
            liquidity: liquidity,
            transferInMintCallback: false,
            transferInSwapCallback: true,
            mintLiqudity: false
        });
        setupTestCase(params);

        vm.expectRevert(encodeError("InsufficientInputAmount()"));
        pool.mint(address(this), liquidity[0].lowerTick, liquidity[0].upperTick, liquidity[0].amount, "");
    }

    function testFlash() public {
        LiquidityRange[] memory liquidity = new LiquidityRange[](1);
        liquidity[0] = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentPrice: 5000,
            liquidity: liquidity,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiqudity: true
        });
        setupTestCase(params);

        pool.flash(0.1 ether, 1000 ether, abi.encodePacked(uint256(0.1 ether), uint256(1000 ether)));

        assertTrue(flashCallbackCalled, "flash callback wasn't called");
    }

    ////////////////////////////////////////////////////////////////////////////
    //
    // CALLBACKS
    //
    ////////////////////////////////////////////////////////////////////////////

    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata data) public {
        if (transferInMintCallback) {
            IUniswapV3Pool.CallbackData memory extra = abi.decode(data, (IUniswapV3Pool.CallbackData));

            IERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0);
            IERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1);
        }
    }

    function uniswapV3FlashCallback(bytes calldata data) public {
        (uint256 amount0, uint256 amount1) = abi.decode(data, (uint256, uint256));

        if (amount0 > 0) weth.transfer(msg.sender, amount0);
        if (amount1 > 0) usdc.transfer(msg.sender, amount1);

        flashCallbackCalled = true;
    }

    ////////////////////////////////////////////////////////////////////////////
    //
    // INTERNAL
    //
    ////////////////////////////////////////////////////////////////////////////

    function setupTestCase(TestCaseParams memory params)
        internal
        returns (uint256 poolBalance0, uint256 poolBalance1)
    {
        weth.mint(address(this), params.wethBalance);
        usdc.mint(address(this), params.usdcBalance);

        pool = deployPool(factory, address(weth), address(usdc), 60, params.currentPrice);

        if (params.mintLiqudity) {
            weth.approve(address(this), params.wethBalance);
            usdc.approve(address(this), params.usdcBalance);

            bytes memory extra = encodeExtra(address(weth), address(usdc), address(this));

            uint256 poolBalance0Tmp;
            uint256 poolBalance1Tmp;
            for (uint256 i = 0; i < params.liquidity.length; i++) {
                console2.log("UniswapV3PoolTest::setupTestCase::beforeMint");
                (poolBalance0Tmp, poolBalance1Tmp) = pool.mint(
                    address(this),
                    params.liquidity[i].lowerTick,
                    params.liquidity[i].upperTick,
                    params.liquidity[i].amount,
                    extra
                );
                console2.log("UniswapV3PoolTest::setupTestCase::afterMint");
                poolBalance0 += poolBalance0Tmp;
                poolBalance1 += poolBalance1Tmp;
            }
        }

        transferInMintCallback = params.transferInMintCallback;
    }
}
