// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.29;

/// @title FixedPoint128 Library
/// @notice Defines constants for fixed-point arithmetic with 128-bit resolution
library FixedPoint128 {
    /// @notice The resolution of fixed-point numbers (128 bits)
    uint8 internal constant RESOLUTION = 128;
    /// @notice The scaling factor for Q128.96 fixed-point numbers
    uint256 internal constant Q128 = 2 ** 128;
}
