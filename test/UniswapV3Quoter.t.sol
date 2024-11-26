// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test, stdError } from "forge-std/Test.sol";

import { UniswapV3Quoter } from "src/UniswapV3Quoter.sol";
import { UniswapV3Pool, IERC20 } from "src/UniswapV3Pool.sol";
import { UniswapV3Manager } from "src/UniswapV3Manager.sol";
import { ERC20Mintable } from "test/mocks/MintableERC20.sol";

contract UniswapV3QuoterTest is Test {
    ERC20Mintable token0;
    ERC20Mintable token1;
    UniswapV3Pool pool;
    UniswapV3Manager manager;
    UniswapV3Quoter quoter;

    function setUp() public {
        token0 = new ERC20Mintable("Ether", "ETH", 18);
        token1 = new ERC20Mintable("USDC", "USDC", 18);

        uint256 wethBalance = 100 ether;
        uint256 usdcBalance = 1_000_000 ether;

        token0.mint(address(this), wethBalance);
        token1.mint(address(this), usdcBalance);

        pool = new UniswapV3Pool(address(token0), address(token1), 5_602_277_097_478_614_198_912_276_234_240, 85_176);

        manager = new UniswapV3Manager();

        token0.approve(address(manager), wethBalance);
        token1.approve(address(manager), usdcBalance);

        int24 lowerTick = 84_222;
        int24 upperTick = 86_129;
        uint128 liquidity = 1_517_882_343_751_509_868_544;
        bytes memory extra = encodeExtra(address(token0), address(token1), address(this));

        manager.mint(address(pool), lowerTick, upperTick, liquidity, extra);

        quoter = new UniswapV3Quoter();
    }

    function test_Quote_USDCforETH() public {
        (uint256 amountOut, uint256 sqrtPriceX96After, int24 tickAfter) = quoter.quote(
            UniswapV3Quoter.QuoteParams({ pool: address(pool), amountIn: 0.01337 ether, zeroForOne: true })
        );

        assertEq(amountOut, 66.808388890199406685 ether, "invalid amountOut");
        assertEq(sqrtPriceX96After, 5_598_789_932_670_288_701_514_545_755_210, "invalid sqrtPriceX96After");
        assertEq(tickAfter, 85_163, "invalid tickAfter");
    }

    function test_Quote_ETHforUSDC() public {
        (uint256 amountOut, uint256 sqrtPriceX96After, int24 tickAfter) =
            quoter.quote(UniswapV3Quoter.QuoteParams({ pool: address(pool), amountIn: 42 ether, zeroForOne: false }));

        assertEq(amountOut, 0.008396714242162445 ether, "invalid amountOut");
        assertEq(sqrtPriceX96After, 5_604_469_350_942_327_889_444_743_441_197, "invalid sqrtPriceX96After");
        assertEq(tickAfter, 85_184, "invalid tickAfter");
    }

    function test_QuoteAndSwap_USDCforETH() public {
        uint256 amountIn = 0.01337 ether;
        (uint256 amountOut,,) =
            quoter.quote(UniswapV3Quoter.QuoteParams({ pool: address(pool), amountIn: amountIn, zeroForOne: true }));

        bytes memory extra = encodeExtra(address(token0), address(token1), address(this));

        (int256 amount0Delta, int256 amount1Delta) = manager.swap(address(pool), true, amountIn, extra);

        assertEq(uint256(amount0Delta), amountIn, "invalid amount0Delta");
        assertEq(uint256(-amount1Delta), amountOut, "invalid amount1Delta");
    }

    function test_QuoteAndSwap_ETHforUSDC() public {
        uint256 amountIn = 55 ether;
        (uint256 amountOut,,) =
            quoter.quote(UniswapV3Quoter.QuoteParams({ pool: address(pool), amountIn: amountIn, zeroForOne: false }));

        bytes memory extra = encodeExtra(address(token0), address(token1), address(this));

        (int256 amount0Delta, int256 amount1Delta) = manager.swap(address(pool), false, amountIn, extra);

        assertEq(uint256(-amount0Delta), amountOut, "invalid amount0Delta");
        assertEq(uint256(amount1Delta), amountIn, "invalid amount1Delta");
    }

    function encodeExtra(address _token0, address _token1, address _payer) internal pure returns (bytes memory) {
        return abi.encode(UniswapV3Pool.CallbackData({ token0: _token0, token1: _token1, payer: _payer }));
    }
}
