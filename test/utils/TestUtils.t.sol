// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { Test, stdError, console2 } from "forge-std/Test.sol";

import { TestUtils } from "./TestUtils.sol";

contract TestUtilsTest is Test, TestUtils {
    function testNearestUsableTick() public {
        assertEq(nearestUsableTick(85_176, 60), 85_200);
        assertEq(nearestUsableTick(85_170, 60), 85_200);
        assertEq(nearestUsableTick(85_169, 60), 85_140);

        assertEq(nearestUsableTick(85_200, 60), 85_200);
        assertEq(nearestUsableTick(85_140, 60), 85_140);
    }

    function testTick60() public {
        assertEq(tick60(5000), 85_200);
        assertEq(tick60(4545), 84_240);
        assertEq(tick60(6250), 87_420);
    }

    function testSqrtP60() public {
        assertEq(sqrtP60(5000), 5_608_950_122_784_459_951_015_918_491_039);
        assertEq(sqrtP60(4545), 5_346_092_701_810_166_522_520_541_901_099);
        assertEq(sqrtP60(6250), 6_267_377_518_277_060_417_829_549_285_552);
    }
}
