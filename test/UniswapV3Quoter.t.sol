// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test, stdError } from "forge-std/Test.sol";

import { UniswapV3Quoter } from "src/UniswapV3Quoter.sol";
import { UniswapV3Pool, IERC20 } from "src/UniswapV3Pool.sol";
import { UniswapV3Manager, IUniswapV3Manager } from "src/UniswapV3Manager.sol";
import { UniswapV3Factory } from "src/UniswapV3Factory.sol";
import { ERC20Mock } from "test/mocks/ERC20Mock.sol";
import { TestUtils } from "./utils/TestUtils.sol";

contract UniswapV3QuoterTest is Test, TestUtils {
    ERC20Mock weth;
    ERC20Mock usdc;
    ERC20Mock uni;
    UniswapV3Pool wethUSDC;
    UniswapV3Pool wethUNI;
    UniswapV3Manager manager;
    UniswapV3Quoter quoter;
    UniswapV3Factory factory;

    function setUp() public {
        usdc = new ERC20Mock("USDC", "USDC");
        weth = new ERC20Mock("Wrapped Ether", "WETH");
        uni = new ERC20Mock("Uniswap coin", "UNI");
        factory = new UniswapV3Factory();

        uint256 wethBalance = 100 ether;
        uint256 usdcBalance = 1_000_000 ether;
        uint256 uniBalance = 1000 ether;

        weth.mint(address(this), wethBalance);
        usdc.mint(address(this), usdcBalance);
        uni.mint(address(this), uniBalance);

        wethUSDC = deployPool(factory, address(weth), address(usdc), 60, 5000);
        wethUNI = deployPool(factory, address(weth), address(uni), 60, 10);

        manager = new UniswapV3Manager(address(factory));

        weth.approve(address(manager), wethBalance);
        usdc.approve(address(manager), usdcBalance);
        uni.approve(address(manager), uniBalance);

        manager.mint(
            IUniswapV3Manager.MintParams({
                tokenA: address(weth),
                tokenB: address(usdc),
                tickSpacing: 60,
                lowerTick: tick60(4545),
                upperTick: tick60(5500),
                amount0Desired: 1 ether,
                amount1Desired: 5000 ether,
                amount0Min: 0,
                amount1Min: 0
            })
        );

        manager.mint(
            IUniswapV3Manager.MintParams({
                tokenA: address(weth),
                tokenB: address(uni),
                tickSpacing: 60,
                lowerTick: tick60(7),
                upperTick: tick60(13),
                amount0Desired: 10 ether,
                amount1Desired: 100 ether,
                amount0Min: 0,
                amount1Min: 0
            })
        );

        quoter = new UniswapV3Quoter(address(factory));
    }

    function testQuoteUSDCforETH() public {
        (uint256 amountOut, uint160 sqrtPriceX96After, int24 tickAfter) = quoter.quoteSingle(
            UniswapV3Quoter.QuoteSingleParams({
                tokenIn: address(weth),
                tokenOut: address(usdc),
                tickSpacing: 60,
                amountIn: 0.01337 ether,
                sqrtPriceLimitX96: sqrtP(4993)
            })
        );

        assertEq(amountOut, 66.809153442256308009 ether, "invalid amountOut");
        assertEq(
            sqrtPriceX96After,
            5_598_854_004_958_668_990_019_104_567_840, // 4993.891686050662
            "invalid sqrtPriceX96After"
        );
        assertEq(tickAfter, 85_163, "invalid tickAFter");
    }

    function testQuoteETHforUSDC() public {
        (uint256 amountOut, uint160 sqrtPriceX96After, int24 tickAfter) = quoter.quoteSingle(
            UniswapV3Quoter.QuoteSingleParams({
                tokenIn: address(usdc),
                tokenOut: address(weth),
                tickSpacing: 60,
                amountIn: 42 ether,
                sqrtPriceLimitX96: sqrtP(5005)
            })
        );

        assertEq(amountOut, 0.008396774627565324 ether, "invalid amountOut");
        assertEq(
            sqrtPriceX96After,
            5_604_429_046_402_228_950_611_610_935_846, // 5003.841941749589
            "invalid sqrtPriceX96After"
        );
        assertEq(tickAfter, 85_183, "invalid tickAFter");
    }

    function testQuoteAndSwapUSDCforETH() public {
        uint256 amountIn = 0.01337 ether;
        (uint256 amountOut,,) = quoter.quoteSingle(
            UniswapV3Quoter.QuoteSingleParams({
                tokenIn: address(weth),
                tokenOut: address(usdc),
                tickSpacing: 60,
                amountIn: amountIn,
                sqrtPriceLimitX96: sqrtP(4993)
            })
        );

        IUniswapV3Manager.SwapSingleParams memory swapParams = IUniswapV3Manager.SwapSingleParams({
            tokenIn: address(weth),
            tokenOut: address(usdc),
            tickSpacing: 60,
            amountIn: amountIn,
            sqrtPriceLimitX96: sqrtP(4993)
        });
        uint256 amountOutActual = manager.swapSingle(swapParams);

        assertEq(amountOutActual, amountOut, "invalid amount1Delta");
    }

    function testQuoteAndSwapETHforUSDC() public {
        uint256 amountIn = 55 ether;
        (uint256 amountOut,,) = quoter.quoteSingle(
            UniswapV3Quoter.QuoteSingleParams({
                tokenIn: address(usdc),
                tokenOut: address(weth),
                tickSpacing: 60,
                amountIn: amountIn,
                sqrtPriceLimitX96: sqrtP(5010)
            })
        );

        IUniswapV3Manager.SwapSingleParams memory swapParams = IUniswapV3Manager.SwapSingleParams({
            tokenIn: address(usdc),
            tokenOut: address(weth),
            tickSpacing: 60,
            amountIn: amountIn,
            sqrtPriceLimitX96: sqrtP(5010)
        });
        uint256 amountOutActual = manager.swapSingle(swapParams);

        assertEq(amountOutActual, amountOut, "invalid amount0Delta");
    }

    /**
     * UNI -> ETH -> USDC
     *    10/1   1/5000
     */
    function testQuoteUNIforUSDCviaETH() public {
        bytes memory path = bytes.concat(
            bytes20(address(uni)),
            bytes3(uint24(60)),
            bytes20(address(weth)),
            bytes3(uint24(60)),
            bytes20(address(usdc))
        );
        (uint256 amountOut, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList) =
            quoter.quote(path, 3 ether);

        assertEq(amountOut, 1472.545906750265420689 ether, "invalid amountOut");
        assertEq(
            sqrtPriceX96AfterList[0],
            251_775_459_842_086_338_964_181_233_032, // 10.098750163842778
            "invalid sqrtPriceX96After"
        );
        assertEq(
            sqrtPriceX96AfterList[1],
            5_526_828_440_835_641_442_318_026_170_540, // 4866.231885685384
            "invalid sqrtPriceX96After"
        );
        assertEq(tickAfterList[0], 23_125, "invalid tickAFter");
        assertEq(tickAfterList[1], 84_904, "invalid tickAFter");
    }

    /**
     * UNI -> ETH -> USDC
     *    10/1   1/5000
     */
    function testQuoteAndSwapUNIforUSDCviaETH() public {
        uint256 amountIn = 3 ether;
        bytes memory path = bytes.concat(
            bytes20(address(uni)),
            bytes3(uint24(60)),
            bytes20(address(weth)),
            bytes3(uint24(60)),
            bytes20(address(usdc))
        );
        (uint256 amountOut,,) = quoter.quote(path, amountIn);

        uint256 amountOutActual = manager.swap(
            IUniswapV3Manager.SwapParams({
                path: path,
                recipient: address(this),
                amountIn: amountIn,
                minAmountOut: amountOut
            })
        );

        assertEq(amountOutActual, amountOut, "invalid amount1Delta");
    }
}
