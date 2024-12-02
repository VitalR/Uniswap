// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/// @title Position Library
/// @notice Manages liquidity positions
library Position {
    /// @notice Represents information about a liquidity position
    /// @param liquidity The total liquidity associated with the position
    struct Info {
        uint128 liquidity;
    }

    /// @notice Updates the liquidity of a position
    /// @param self The position to update
    /// @param liquidityDelta The change in liquidity to apply (positive or negative)
    function update(Info storage self, uint128 liquidityDelta) internal {
        uint128 liquidityBefore = self.liquidity;
        uint128 liquidityAfter = liquidityBefore + liquidityDelta;

        self.liquidity = liquidityAfter;
    }

    /// @notice Retrieves a specific position using the owner address and tick range
    /// @param self The mapping of positions
    /// @param owner The address of the position owner
    /// @param lowerTick The lower tick boundary of the position
    /// @param upperTick The upper tick boundary of the position
    /// @return position The position information
    function get(mapping(bytes32 => Info) storage self, address owner, int24 lowerTick, int24 upperTick)
        internal
        view
        returns (Position.Info storage position)
    {
        position = self[keccak256(abi.encodePacked(owner, lowerTick, upperTick))];
    }
}
