// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.29;

/// @title FixedPoint96 Library
/// @notice Defines constants for fixed-point arithmetic with 96-bit resolution
library FixedPoint96 {
    /// @notice The resolution of fixed-point numbers (96 bits)
    uint8 internal constant RESOLUTION = 96;
    /// @notice The scaling factor for Q96.96 fixed-point numbers
    uint256 internal constant Q96 = 2 ** 96;
}
