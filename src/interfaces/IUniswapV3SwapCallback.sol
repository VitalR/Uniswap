// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.29;

interface IUniswapV3SwapCallback {
    function uniswapV3SwapCallback(int256 amount0, int256 amount1, bytes calldata data) external;
}
