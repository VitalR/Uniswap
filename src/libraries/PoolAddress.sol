// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.29;

import { UniswapV3Pool } from "src/UniswapV3Pool.sol";

/// @title PoolAddress
/// @notice A utility library for computing the address of a Uniswap V3 pool.
/// @dev This library calculates the deterministic address of a pool using the CREATE2 opcode.
library PoolAddress {
    /// @notice Computes the address of a Uniswap V3 pool for given parameters.
    /// @dev Ensures that token addresses are sorted (`token0 < token1`) before computation.
    ///      Uses the CREATE2 opcode to compute the pool address deterministically.
    /// @param factory The address of the Uniswap V3 factory contract.
    /// @param token0 The address of the first token in the pool. Must be less than `token1`.
    /// @param token1 The address of the second token in the pool.
    /// @param tickSpacing The tick spacing for the pool.
    /// @return pool The computed address of the Uniswap V3 pool.
    function computeAddress(address factory, address token0, address token1, uint24 tickSpacing)
        internal
        pure
        returns (address pool)
    {
        require(token0 < token1);

        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encodePacked(token0, token1, tickSpacing)),
                            keccak256(type(UniswapV3Pool).creationCode)
                        )
                    )
                )
            )
        );
    }
}
