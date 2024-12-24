// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Base64 } from "@openzeppelin/utils/Base64.sol";
import { Strings } from "@openzeppelin/utils/Strings.sol";

import { IERC20 } from "src/interfaces/IERC20.sol";
import { IUniswapV3Pool } from "src/interfaces/IUniswapV3Pool.sol";

/// @title NFTRenderer Library
/// @notice Provides utilities for rendering SVG-based NFTs and metadata for Uniswap V3 positions.
library NFTRenderer {
    /// @notice Represents the parameters required to render an NFT.
    /// @param pool The address of the Uniswap V3 pool.
    /// @param owner The owner of the position.
    /// @param lowerTick The lower tick of the position's range.
    /// @param upperTick The upper tick of the position's range.
    /// @param fee The fee tier of the pool.
    struct RenderParams {
        address pool;
        address owner;
        int24 lowerTick;
        int24 upperTick;
        uint24 fee;
    }

    /// @notice Renders an NFT with metadata for a given Uniswap V3 position.
    /// @param params The rendering parameters encapsulated in a `RenderParams` struct.
    /// @return A Base64-encoded JSON string containing metadata and an SVG image.
    function render(RenderParams memory params)
        internal
        view
        returns (string memory)
    {
        IUniswapV3Pool pool = IUniswapV3Pool(params.pool);
        IERC20 token0 = IERC20(pool.token0());
        IERC20 token1 = IERC20(pool.token1());
        string memory symbol0 = token0.symbol();
        string memory symbol1 = token1.symbol();

        string memory image = string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 300 480'>",
            "<style>.tokens { font: bold 30px sans-serif; }",
            ".fee { font: normal 26px sans-serif; }",
            ".tick { font: normal 18px sans-serif; }</style>",
            renderBackground(params.owner, params.lowerTick, params.upperTick),
            renderTop(symbol0, symbol1, params.fee),
            renderBottom(params.lowerTick, params.upperTick),
            "</svg>"
        );

        string memory description = renderDescription(
            symbol0,
            symbol1,
            params.fee,
            params.lowerTick,
            params.upperTick
        );

        string memory json = string.concat(
            '{"name":"Uniswap V3 Position",',
            '"description":"',
            description,
            '",',
            '"image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(image)),
            '"}'
        );

        return
            string.concat(
                "data:application/json;base64,",
                Base64.encode(bytes(json))
            );
    }

    ////////////////////////////////////////////////////////////////////////////
    //
    // INTERNAL
    //
    ////////////////////////////////////////////////////////////////////////////
    
    /// @notice Generates the background SVG for the NFT.
    /// @param owner The address of the position owner.
    /// @param lowerTick The lower tick of the position's range.
    /// @param upperTick The upper tick of the position's range.
    /// @return background The SVG string representing the background.    
    function renderBackground(
        address owner,
        int24 lowerTick,
        int24 upperTick
    ) internal pure returns (string memory background) {
        bytes32 key = keccak256(abi.encodePacked(owner, lowerTick, upperTick));
        uint256 hue = uint256(key) % 360;

        background = string.concat(
            '<rect width="300" height="480" fill="hsl(',
            Strings.toString(hue),
            ',40%,40%)"/>',
            '<rect x="30" y="30" width="240" height="420" rx="15" ry="15" fill="hsl(',
            Strings.toString(hue),
            ',100%,50%)" stroke="#000"/>'
        );
    }

    /// @notice Renders the top section of the NFT, including token symbols and the fee tier.
    /// @param symbol0 The symbol of the first token in the pair.
    /// @param symbol1 The symbol of the second token in the pair.
    /// @param fee The fee tier of the pool.
    /// @return top The SVG string representing the top section.
    function renderTop(
        string memory symbol0,
        string memory symbol1,
        uint24 fee
    ) internal pure returns (string memory top) {
        top = string.concat(
            '<rect x="30" y="87" width="240" height="42"/>',
            '<text x="39" y="120" class="tokens" fill="#fff">',
            symbol0,
            "/",
            symbol1,
            "</text>"
            '<rect x="30" y="132" width="240" height="30"/>',
            '<text x="39" y="120" dy="36" class="fee" fill="#fff">',
            feeToText(fee),
            "</text>"
        );
    }

    /// @notice Renders the bottom section of the NFT, including the lower and upper ticks.
    /// @param lowerTick The lower tick of the position's range.
    /// @param upperTick The upper tick of the position's range.
    /// @return bottom The SVG string representing the bottom section.
    function renderBottom(int24 lowerTick, int24 upperTick)
        internal
        pure
        returns (string memory bottom)
    {
        bottom = string.concat(
            '<rect x="30" y="342" width="240" height="24"/>',
            '<text x="39" y="360" class="tick" fill="#fff">Lower tick: ',
            tickToText(lowerTick),
            "</text>",
            '<rect x="30" y="372" width="240" height="24"/>',
            '<text x="39" y="360" dy="30" class="tick" fill="#fff">Upper tick: ',
            tickToText(upperTick),
            "</text>"
        );
    }

    /// @notice Renders the description metadata for the NFT.
    /// @param symbol0 The symbol of the first token in the pair.
    /// @param symbol1 The symbol of the second token in the pair.
    /// @param fee The fee tier of the pool.
    /// @param lowerTick The lower tick of the position's range.
    /// @param upperTick The upper tick of the position's range.
    /// @return description The metadata description string.
    function renderDescription(
        string memory symbol0,
        string memory symbol1,
        uint24 fee,
        int24 lowerTick,
        int24 upperTick
    ) internal pure returns (string memory description) {
        description = string.concat(
            symbol0,
            "/",
            symbol1,
            " ",
            feeToText(fee),
            ", Lower tick: ",
            tickToText(lowerTick),
            ", Upper text: ",
            tickToText(upperTick)
        );
    }

    /// @notice Converts a fee tier to its textual representation.
    /// @param fee The fee tier as an integer.
    /// @return feeString The textual representation of the fee tier.
    function feeToText(uint256 fee)
        internal
        pure
        returns (string memory feeString)
    {
        if (fee == 500) {
            feeString = "0.05%";
        } else if (fee == 3000) {
            feeString = "0.3%";
        }
    }

    /// @notice Converts a tick value to its textual representation.
    /// @param tick The tick value as an integer.
    /// @return tickString The textual representation of the tick value.
    function tickToText(int24 tick)
        internal
        pure
        returns (string memory tickString)
    {
        tickString = string.concat(
            tick < 0 ? "-" : "",
            tick < 0
                ? Strings.toString(uint256(uint24(-tick)))
                : Strings.toString(uint256(uint24(tick)))
        );
    }
}