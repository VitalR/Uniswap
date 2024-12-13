// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test, stdError } from "forge-std/Test.sol";

import { UniswapV3Pool, IUniswapV3Pool, IERC20 } from "src/UniswapV3Pool.sol";
import { UniswapV3Factory } from "src/UniswapV3Factory.sol";
import { TestUtils } from "./utils/TestUtils.sol";
import { ERC20Mock } from "test/mocks/ERC20Mock.sol";

contract UniswapV3FactoryTest is Test, TestUtils {
    ERC20Mock weth;
    ERC20Mock usdc;
    // UniswapV3Pool pool;
    UniswapV3Factory factory;

    function setUp() public {
        usdc = new ERC20Mock("USDC", "USDC");
        weth = new ERC20Mock("Wrapped Ether", "WETH");
        factory = new UniswapV3Factory();
    }

    function testCreatePool() public {
        address poolAddress = factory.createPool(address(weth), address(usdc), 500);

        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

        assertEq(factory.pools(address(usdc), address(weth), 500), poolAddress, "invalid pool address in the registry");

        assertEq(
            factory.pools(address(weth), address(usdc), 500),
            poolAddress,
            "invalid pool address in the registry (reverse order)"
        );

        assertEq(pool.factory(), address(factory), "invalid factory address");
        assertEq(pool.token0(), address(weth), "invalid weth address");
        assertEq(pool.token1(), address(usdc), "invalid usdc address");
        assertEq(pool.tickSpacing(), 10, "invalid tick spacing");
        assertEq(pool.fee(), 500, "invalid fee");

        (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext
        ) = pool.slot0();
        assertEq(sqrtPriceX96, 0, "invalid sqrtPriceX96");
        assertEq(tick, 0, "invalid tick");
        assertEq(observationIndex, 0, "invalid observation index");
        assertEq(observationCardinality, 0, "invalid observation cardinality");
        assertEq(observationCardinalityNext, 0, "invalid next observation cardinality");
    }

    function testCreatePoolUnsupportedFee() public {
        vm.expectRevert(encodeError("UnsupportedFee()"));
        factory.createPool(address(weth), address(usdc), 300);
    }

    function testCreatePoolIdenticalTokens() public {
        vm.expectRevert(encodeError("TokensMustBeDifferent()"));
        factory.createPool(address(weth), address(weth), 500);
    }

    function testCreateZeroTokenAddress() public {
        vm.expectRevert(encodeError("ZeroAddressNotAllowed()"));
        factory.createPool(address(weth), address(0), 500);
    }

    function testCreateAlreadyExists() public {
        factory.createPool(address(weth), address(usdc), 500);

        vm.expectRevert(encodeError("PoolAlreadyExists()"));
        factory.createPool(address(weth), address(usdc), 500);
    }
}
