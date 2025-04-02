// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.29;

/// @title IUniswapV3PoolDeployer
/// @notice Interface for the Uniswap V3 pool deployer.
interface IUniswapV3PoolDeployer {
    /// @notice Thrown when a pool already exists for the given parameters.
    error PoolAlreadyExists();
    /// @notice Thrown when a zero address is used for tokens.
    error ZeroAddressNotAllowed();
    /// @notice Thrown when both tokens are the same.
    error TokensMustBeDifferent();
    /// @notice Thrown when an unsupported fee is used.
    error UnsupportedFee();

    struct PoolParameters {
        /// @notice The address of the factory that deployed the pool.
        address factory;
        /// @notice The address of token0.
        address token0;
        /// @notice The address of token1.
        address token1;
        /// @notice The tick spacing for the pool.
        uint24 tickSpacing;
        /// @notice The fee tier for the pool.
        uint24 fee;
    }

    /// @notice Emitted when a new pool is created.
    /// @param token0 The address of the first token in the pool.
    /// @param token1 The address of the second token in the pool.
    /// @param fee The fee for the pool.
    /// @param pool The address of the created pool.
    event PoolCreated(address indexed token0, address indexed token1, uint24 indexed fee, address pool);

    /// @notice Returns the parameters of the pool being deployed.
    /// @return factory The address of the factory deploying the pool.
    /// @return token0 The address of token0.
    /// @return token1 The address of token1.
    /// @return tickSpacing The tick spacing for the pool.
    /// @return fee ..
    function parameters() external returns (address factory, address token0, address token1, uint24 tickSpacing, uint24 fee);
}
