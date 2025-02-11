// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Test, stdError } from "forge-std/Test.sol";

import { Math } from "src/libraries/Math.sol";
import { TickMath } from "src/libraries/TickMath.sol";

contract MathTest is Test {
    function testCalcAmount0Delta() public {
        int256 amount0 = Math.calcAmount0Delta(
            TickMath.getSqrtRatioAtTick(85_176),
            TickMath.getSqrtRatioAtTick(86_129),
            int128(1_517_882_343_751_509_868_544)
        );

        assertEq(amount0, 0.998833192822975409 ether);
    }

    function testCalcAmount1Delta() public {
        int256 amount1 = Math.calcAmount1Delta(
            TickMath.getSqrtRatioAtTick(84_222),
            TickMath.getSqrtRatioAtTick(85_176),
            int128(1_517_882_343_751_509_868_544)
        );

        assertEq(amount1, 4999.187247111820044641 ether);
    }

    function testCalcAmount0DeltaNegative() public {
        int256 amount0 = Math.calcAmount0Delta(
            TickMath.getSqrtRatioAtTick(85_176),
            TickMath.getSqrtRatioAtTick(86_129),
            int128(-1_517_882_343_751_509_868_544)
        );

        assertEq(amount0, -0.998833192822975408 ether);
    }

    function testCalcAmount1DeltaNegative() public {
        int256 amount1 = Math.calcAmount1Delta(
            TickMath.getSqrtRatioAtTick(84_222),
            TickMath.getSqrtRatioAtTick(85_176),
            int128(-1_517_882_343_751_509_868_544)
        );

        assertEq(amount1, -4999.18724711182004464 ether);
    }
}
