// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IUniswapV3PoolDeployer } from "./interfaces/IUniswapV3PoolDeployer.sol";
import { UniswapV3Pool } from "src/UniswapV3Pool.sol";

/// @title UniswapV3Factory
/// @notice The factory contract for deploying and managing Uniswap V3 pools.
/// @dev This contract allows creation of new Uniswap V3 pools with specific tokens and tick spacing.
contract UniswapV3Factory is IUniswapV3PoolDeployer {
    /// @notice The parameters of the pool currently being deployed.
    PoolParameters public parameters;

    /// @notice Supported tick spacings for pools.
    mapping(uint24 => bool) public tickSpacings;

    /// @notice A mapping of token pairs and tick spacing to their corresponding pool addresses.
    /// @dev Pools are indexed by `[token0][token1][tickSpacing]`.
    mapping(address => mapping(address => mapping(uint24 => address))) public pools;

    /// @notice Constructor initializes supported tick spacings.
    constructor() {
        tickSpacings[10] = true;
        tickSpacings[60] = true;
    }

    /// @notice Creates a new Uniswap V3 pool with the specified parameters.
    /// @dev Ensures tokens are different and sorted, and the pool doesn't already exist.
    ///      Uses CREATE2 to deploy the pool contract deterministically.
    /// @param tokenX One of the tokens for the pool.
    /// @param tokenY The other token for the pool.
    /// @param tickSpacing The tick spacing for the pool.
    /// @return pool The address of the newly created pool.
    function createPool(address tokenX, address tokenY, uint24 tickSpacing) public returns (address pool) {
        if (tokenX == tokenY) revert TokensMustBeDifferent();
        if (!tickSpacings[tickSpacing]) revert UnsupportedTickSpacing();

        (tokenX, tokenY) = tokenX < tokenY ? (tokenX, tokenY) : (tokenY, tokenX);

        if (tokenX == address(0)) revert ZeroAddressNotAllowed();
        if (pools[tokenX][tokenY][tickSpacing] != address(0)) {
            revert PoolAlreadyExists();
        }

        parameters =
            PoolParameters({ factory: address(this), token0: tokenX, token1: tokenY, tickSpacing: tickSpacing });

        pool = address(new UniswapV3Pool{ salt: keccak256(abi.encodePacked(tokenX, tokenY, tickSpacing)) }());

        delete parameters;

        pools[tokenX][tokenY][tickSpacing] = pool;
        pools[tokenY][tokenX][tickSpacing] = pool;

        emit PoolCreated(tokenX, tokenY, tickSpacing, pool);
    }
}
