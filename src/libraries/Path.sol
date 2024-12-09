// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.25;

import "bytes-utils/BytesLib.sol";

/// @title BytesLibExt
/// @notice A library extending `BytesLib` with additional utility functions for handling byte arrays.
library BytesLibExt {
    /// @notice Extracts a `uint24` value from a byte array starting at the specified index.
    /// @dev This function reads three bytes starting from `_start` and converts them into a `uint24`.
    /// @param _bytes The byte array to extract the value from.
    /// @param _start The starting index in the byte array.
    /// @return tempUint The extracted `uint24` value.
    /// @custom:throws "toUint24_outOfBounds" if `_start + 3` exceeds the length of `_bytes`.
    function toUint24(bytes memory _bytes, uint256 _start) internal pure returns (uint24) {
        require(_bytes.length >= _start + 3, "toUint24_outOfBounds");
        uint24 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x3), _start))
        }

        return tempUint;
    }
}

/// @title Path
/// @notice A library for parsing and managing encoded Uniswap V3 swap paths.
/// @dev Provides functions to work with byte-encoded swap paths, including extracting pool information and navigating paths.
library Path {
    using BytesLib for bytes;
    using BytesLibExt for bytes;

    /// @dev The length of a bytes-encoded token address.
    uint256 private constant ADDR_SIZE = 20;
    /// @dev The length of a bytes-encoded tick spacing value.
    uint256 private constant TICKSPACING_SIZE = 3;

    /// @dev The offset for a single token address and tick spacing.
    uint256 private constant NEXT_OFFSET = ADDR_SIZE + TICKSPACING_SIZE;
    /// @dev The offset for an encoded pool key (tokenIn + tick spacing + tokenOut).
    uint256 private constant POP_OFFSET = NEXT_OFFSET + ADDR_SIZE;
    /// @dev The minimum length of a path containing two or more pools.
    uint256 private constant MULTIPLE_POOLS_MIN_LENGTH = POP_OFFSET + NEXT_OFFSET;

    /// @notice Checks if the path contains multiple pools.
    /// @param path The byte-encoded swap path.
    /// @return True if the path has multiple pools, false otherwise.
    function hasMultiplePools(bytes memory path) internal pure returns (bool) {
        return path.length >= MULTIPLE_POOLS_MIN_LENGTH;
    }

    /// @notice Calculates the number of pools in the path.
    /// @param path The byte-encoded swap path.
    /// @return The number of pools in the path.
    function numPools(bytes memory path) internal pure returns (uint256) {
        return (path.length - ADDR_SIZE) / NEXT_OFFSET;
    }

    /// @notice Extracts the first pool from the path.
    /// @param path The byte-encoded swap path.
    /// @return The byte representation of the first pool (tokenIn + tick spacing + tokenOut).
    function getFirstPool(bytes memory path) internal pure returns (bytes memory) {
        return path.slice(0, POP_OFFSET);
    }

    /// @notice Skips the first token in the path and returns the remaining path.
    /// @param path The byte-encoded swap path.
    /// @return The remaining path after skipping the first token.
    function skipToken(bytes memory path) internal pure returns (bytes memory) {
        return path.slice(NEXT_OFFSET, path.length - NEXT_OFFSET);
    }

    /// @notice Decodes the first pool in the path into its components.
    /// @param path The byte-encoded swap path.
    /// @return tokenIn The address of the input token for the first pool.
    /// @return tokenOut The address of the output token for the first pool.
    /// @return tickSpacing The tick spacing for the first pool.
    function decodeFirstPool(bytes memory path)
        internal
        pure
        returns (address tokenIn, address tokenOut, uint24 tickSpacing)
    {
        tokenIn = path.toAddress(0);
        tickSpacing = path.toUint24(ADDR_SIZE);
        tokenOut = path.toAddress(NEXT_OFFSET);
    }
}
