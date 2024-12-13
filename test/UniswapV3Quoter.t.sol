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

        wethUSDC = deployPool(factory, address(weth), address(usdc), 3000, 5000);
        wethUNI = deployPool(factory, address(weth), address(uni), 3000, 10);

        manager = new UniswapV3Manager(address(factory));

        weth.approve(address(manager), wethBalance);
        usdc.approve(address(manager), usdcBalance);
        uni.approve(address(manager), uniBalance);

        manager.mint(
            IUniswapV3Manager.MintParams({
                tokenA: address(weth),
                tokenB: address(usdc),
                fee: 3000,
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
                fee: 3000,
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
                fee: 3000,
                amountIn: 0.01337 ether,
                sqrtPriceLimitX96: sqrtP(4993)
            })
        );

        assertEq(amountOut, 66.608848079558229697 ether, "invalid amountOut");
        assertEq(
            sqrtPriceX96After,
            5_598_864_267_980_327_381_293_641_469_695, // 4993.909994249256
            "invalid sqrtPriceX96After"
        );
        assertEq(tickAfter, 85_164, "invalid tickAFter");
    }

    function testQuoteETHforUSDC() public {
        (uint256 amountOut, uint160 sqrtPriceX96After, int24 tickAfter) = quoter.quoteSingle(
            UniswapV3Quoter.QuoteSingleParams({
                tokenIn: address(usdc),
                tokenOut: address(weth),
                fee: 3000,
                amountIn: 42 ether,
                sqrtPriceLimitX96: sqrtP(5005)
            })
        );

        assertEq(amountOut, 0.008371593947078467 ether, "invalid amountOut");
        assertEq(
            sqrtPriceX96After,
            5_604_422_590_555_458_105_735_383_351_329, // 5003.830413717752
            "invalid sqrtPriceX96After"
        );
        assertEq(tickAfter, 85_183, "invalid tickAFter");
    }

    /**
     * UNI -> ETH -> USDC
     *    10/1   1/5000
     */
    function testQuoteUNIforUSDCviaETH() public {
        bytes memory path = bytes.concat(
            bytes20(address(uni)),
            bytes3(uint24(3000)),
            bytes20(address(weth)),
            bytes3(uint24(3000)),
            bytes20(address(usdc))
        );
        (uint256 amountOut, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList) =
            quoter.quote(path, 3 ether);

        assertEq(amountOut, 1463.863228593034635225 ether, "invalid amountOut");
        assertEq(
            sqrtPriceX96AfterList[0],
            251_771_757_807_685_223_741_030_010_328, // 10.098453187753986
            "invalid sqrtPriceX96After"
        );
        assertEq(
            sqrtPriceX96AfterList[1],
            5_527_273_314_166_940_201_896_143_730_186, // 4867.015316523305
            "invalid sqrtPriceX96After"
        );
        assertEq(tickAfterList[0], 23_124, "invalid tickAFter");
        assertEq(tickAfterList[1], 84_906, "invalid tickAFter");
    }

    /**
     * UNI -> ETH -> USDC
     *    10/1   1/5000
     */
    function testQuoteAndSwapUNIforUSDCviaETH() public {
        uint256 amountIn = 3 ether;
        bytes memory path = bytes.concat(
            bytes20(address(uni)),
            bytes3(uint24(3000)),
            bytes20(address(weth)),
            bytes3(uint24(3000)),
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

    function testQuoteAndSwapUSDCforETH() public {
        uint256 amountIn = 0.01337 ether;
        (uint256 amountOut,,) = quoter.quoteSingle(
            UniswapV3Quoter.QuoteSingleParams({
                tokenIn: address(weth),
                tokenOut: address(usdc),
                fee: 3000,
                amountIn: amountIn,
                sqrtPriceLimitX96: sqrtP(4993)
            })
        );

        IUniswapV3Manager.SwapSingleParams memory swapParams = IUniswapV3Manager.SwapSingleParams({
            tokenIn: address(weth),
            tokenOut: address(usdc),
            fee: 3000,
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
                fee: 3000,
                amountIn: amountIn,
                sqrtPriceLimitX96: sqrtP(5010)
            })
        );

        IUniswapV3Manager.SwapSingleParams memory swapParams = IUniswapV3Manager.SwapSingleParams({
            tokenIn: address(usdc),
            tokenOut: address(weth),
            fee: 3000,
            amountIn: amountIn,
            sqrtPriceLimitX96: sqrtP(5010)
        });
        uint256 amountOutActual = manager.swapSingle(swapParams);

        assertEq(amountOutActual, amountOut, "invalid amount0Delta");
    }
}
