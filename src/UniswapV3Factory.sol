// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IUniswapV3PoolDeployer } from "./interfaces/IUniswapV3PoolDeployer.sol";
import { UniswapV3Pool } from "src/UniswapV3Pool.sol";

/// @title UniswapV3Factory
/// @notice The factory contract for deploying and managing Uniswap V3 pools.
/// @dev This contract allows creation of new Uniswap V3 pools with specific tokens and tick spacing.
contract UniswapV3Factory is IUniswapV3PoolDeployer {
    /// @notice The parameters of the pool currently being deployed.
    /// @dev These parameters are used during the creation of a new pool and cleared after deployment.
    PoolParameters public parameters;

    /// @notice A mapping of fee tiers to their corresponding tick spacings.
    /// @dev Fee tiers must be registered in this mapping before pools with those fees can be created.
    mapping(uint24 => uint24) public fees;

    /// @notice A mapping of token pairs and fees to their corresponding pool addresses.
    /// @dev Pools are indexed by `[token0][token1][fee]` where `token0` < `token1`.
    mapping(address => mapping(address => mapping(uint24 => address))) public pools;

    /// @notice Constructor initializes the factory with supported fee tiers and their tick spacings.
    /// @dev Fee tiers of 500 and 3000 are initialized with tick spacings of 10 and 60, respectively.
    constructor() {
        fees[500] = 10;
        fees[3000] = 60;
    }

    /// @notice Creates a new Uniswap V3 pool with the specified parameters.
    /// @dev Ensures the tokens are different, sorted, and the pool does not already exist. Uses CREATE2 for
    /// deterministic pool addresses.
    /// @param tokenX One of the tokens for the pool.
    /// @param tokenY The other token for the pool.
    /// @param fee The fee tier for the pool, expressed in hundredths of a bip (e.g., 500 = 0.05%, 3000 = 0.3%).
    /// @return pool The address of the newly created pool.
    function createPool(address tokenX, address tokenY, uint24 fee) public returns (address pool) {
        if (tokenX == tokenY) revert TokensMustBeDifferent();
        if (fees[fee] == 0) revert UnsupportedFee();

        (tokenX, tokenY) = tokenX < tokenY ? (tokenX, tokenY) : (tokenY, tokenX);

        if (tokenX == address(0)) revert ZeroAddressNotAllowed();
        if (pools[tokenX][tokenY][fee] != address(0)) {
            revert PoolAlreadyExists();
        }

        parameters =
            PoolParameters({ factory: address(this), token0: tokenX, token1: tokenY, tickSpacing: fees[fee], fee: fee });

        pool = address(new UniswapV3Pool{ salt: keccak256(abi.encodePacked(tokenX, tokenY, fee)) }());

        delete parameters;

        pools[tokenX][tokenY][fee] = pool;
        pools[tokenY][tokenX][fee] = pool;

        emit PoolCreated(tokenX, tokenY, fee, pool);
    }
}
