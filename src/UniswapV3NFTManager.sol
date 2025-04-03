// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.29;

import { ERC721 } from "solmate/tokens/ERC721.sol";

import { IERC20 } from "src/interfaces/IERC20.sol";
import { IUniswapV3Pool } from "src/interfaces/IUniswapV3Pool.sol";
import { LiquidityMath } from "src/libraries/LiquidityMath.sol";
import { NFTRenderer } from "src/libraries/NFTRenderer.sol";
import { PoolAddress } from "src/libraries/PoolAddress.sol";
import { TickMath } from "src/libraries/TickMath.sol";

/// @title UniswapV3NFTManager
/// @notice Manages Uniswap V3 positions as NFTs, enabling minting, adding liquidity, removing liquidity, collecting
/// fees, and burning positions.
contract UniswapV3NFTManager is ERC721 {
    /// @notice Error thrown when the caller is not authorized to perform an action.
    error NotAuthorized();

    /// @notice Error thrown when there is insufficient liquidity available.
    error NotEnoughLiquidity();

    /// @notice Error thrown when a position cannot be burned because it is not cleared.
    error PositionNotCleared();

    /// @notice Error thrown when a slippage check fails during a transaction.
    /// @param amount0 The actual amount of token0 involved.
    /// @param amount1 The actual amount of token1 involved.
    error SlippageCheckFailed(uint256 amount0, uint256 amount1);

    /// @notice Error thrown when an invalid or non-existent token is referenced.
    error WrongToken();

    /// @notice Emitted when liquidity is added to a position.
    /// @param tokenId The ID of the NFT representing the position.
    /// @param liquidity The amount of liquidity added.
    /// @param amount0 The amount of token0 added.
    /// @param amount1 The amount of token1 added.
    event AddLiquidity(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Emitted when liquidity is removed from a position.
    /// @param tokenId The ID of the NFT representing the position.
    /// @param liquidity The amount of liquidity removed.
    /// @param amount0 The amount of token0 removed.
    /// @param amount1 The amount of token1 removed.
    event RemoveLiquidity(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Represents the details of a tokenized Uniswap V3 position.
    /// @param pool The address of the Uniswap V3 pool.
    /// @param lowerTick The lower tick boundary of the position.
    /// @param upperTick The upper tick boundary of the position.
    struct TokenPosition {
        address pool;
        int24 lowerTick;
        int24 upperTick;
    }

    uint256 public totalSupply;
    uint256 private nextTokenId;

    /// @notice The address of the Uniswap V3 factory contract.
    address public immutable factory;

    /// @notice Maps NFT token IDs to their respective Uniswap V3 positions.
    mapping(uint256 => TokenPosition) public positions;

    /// @notice Modifier to ensure the caller is the owner or approved for a given NFT.
    /// @param tokenId The ID of the NFT.
    modifier isApprovedOrOwner(uint256 tokenId) {
        address owner = ownerOf(tokenId);
        if (msg.sender != owner && !isApprovedForAll[owner][msg.sender] && getApproved[tokenId] != msg.sender) {
            revert NotAuthorized();
        }
        _;
    }

    /// @notice Constructs the UniswapV3NFTManager.
    /// @param factoryAddress The address of the Uniswap V3 factory contract.
    constructor(address factoryAddress) ERC721("UniswapV3 NFT Positions", "UNIV3") {
        factory = factoryAddress;
    }

    /// @notice Fetches the metadata URI for a given NFT token ID.
    /// @param tokenId The ID of the NFT.
    /// @return A string containing the token's metadata URI.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        TokenPosition memory tokenPosition = positions[tokenId];
        if (tokenPosition.pool == address(0x00)) revert WrongToken();

        IUniswapV3Pool pool = IUniswapV3Pool(tokenPosition.pool);

        return NFTRenderer.render(
            NFTRenderer.RenderParams({
                pool: tokenPosition.pool,
                owner: address(this),
                lowerTick: tokenPosition.lowerTick,
                upperTick: tokenPosition.upperTick,
                fee: pool.fee()
            })
        );
    }

    /// @notice Parameters for minting a new NFT representing a Uniswap V3 position.
    struct MintParams {
        address recipient;
        address tokenA;
        address tokenB;
        uint24 fee;
        int24 lowerTick;
        int24 upperTick;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    /// @notice Mints a new NFT representing a Uniswap V3 position.
    /// @param params The parameters for minting the position.
    /// @return tokenId The ID of the newly minted NFT.
    function mint(MintParams calldata params) public returns (uint256 tokenId) {
        IUniswapV3Pool pool = getPool(params.tokenA, params.tokenB, params.fee);

        (uint128 liquidity, uint256 amount0, uint256 amount1) = _addLiquidity(
            AddLiquidityInternalParams({
                pool: pool,
                lowerTick: params.lowerTick,
                upperTick: params.upperTick,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min
            })
        );

        tokenId = nextTokenId++;
        _mint(params.recipient, tokenId);
        totalSupply++;

        positions[tokenId] =
            TokenPosition({ pool: address(pool), lowerTick: params.lowerTick, upperTick: params.upperTick });

        emit AddLiquidity(tokenId, liquidity, amount0, amount1);
    }

    /// @notice Parameters for adding liquidity to an existing position.
    struct AddLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    /// @notice Adds liquidity to an existing position.
    /// @param params The parameters for adding liquidity.
    /// @return liquidity The amount of liquidity added.
    /// @return amount0 The amount of token0 added.
    /// @return amount1 The amount of token1 added.
    function addLiquidity(AddLiquidityParams calldata params)
        public
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        TokenPosition memory tokenPosition = positions[params.tokenId];
        if (tokenPosition.pool == address(0x00)) revert WrongToken();

        (liquidity, amount0, amount1) = _addLiquidity(
            AddLiquidityInternalParams({
                pool: IUniswapV3Pool(tokenPosition.pool),
                lowerTick: tokenPosition.lowerTick,
                upperTick: tokenPosition.upperTick,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min
            })
        );

        emit AddLiquidity(params.tokenId, liquidity, amount0, amount1);
    }

    struct RemoveLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
    }

    /// @notice Removes liquidity from an existing position.
    /// @param params The parameters for removing liquidity.
    /// @return amount0 The amount of token0 removed.
    /// @return amount1 The amount of token1 removed.
    function removeLiquidity(RemoveLiquidityParams memory params)
        public
        isApprovedOrOwner(params.tokenId)
        returns (uint256 amount0, uint256 amount1)
    {
        TokenPosition memory tokenPosition = positions[params.tokenId];
        if (tokenPosition.pool == address(0x00)) revert WrongToken();

        IUniswapV3Pool pool = IUniswapV3Pool(tokenPosition.pool);

        (uint128 availableLiquidity,,,,) = pool.positions(poolPositionKey(tokenPosition));
        if (params.liquidity > availableLiquidity) revert NotEnoughLiquidity();

        (amount0, amount1) = pool.burn(tokenPosition.lowerTick, tokenPosition.upperTick, params.liquidity);

        emit RemoveLiquidity(params.tokenId, params.liquidity, amount0, amount1);
    }

    /// @notice Parameters for collecting fees from a position.
    struct CollectParams {
        uint256 tokenId;
        uint128 amount0;
        uint128 amount1;
    }

    /// @notice Collects accrued fees from a Uniswap V3 position.
    /// @dev Requires the caller to be approved or the owner of the token.
    /// @param params The parameters for fee collection, encapsulated in a `CollectParams` struct:
    ///        - tokenId: The ID of the NFT representing the position.
    ///        - amount0: The maximum amount of token0 to collect.
    ///        - amount1: The maximum amount of token1 to collect.
    /// @return amount0 The actual amount of token0 collected.
    /// @return amount1 The actual amount of token1 collected.
    function collect(CollectParams memory params)
        public
        isApprovedOrOwner(params.tokenId)
        returns (uint128 amount0, uint128 amount1)
    {
        TokenPosition memory tokenPosition = positions[params.tokenId];
        if (tokenPosition.pool == address(0x00)) revert WrongToken();

        IUniswapV3Pool pool = IUniswapV3Pool(tokenPosition.pool);

        (amount0, amount1) =
            pool.collect(msg.sender, tokenPosition.lowerTick, tokenPosition.upperTick, params.amount0, params.amount1);
    }

    /// @notice Burns an NFT representing a Uniswap V3 position.
    /// @dev Requires the position to be cleared (no liquidity or tokens owed) before burning.
    /// @param tokenId The ID of the NFT to burn.
    function burn(uint256 tokenId) public isApprovedOrOwner(tokenId) {
        TokenPosition memory tokenPosition = positions[tokenId];
        if (tokenPosition.pool == address(0x00)) revert WrongToken();

        IUniswapV3Pool pool = IUniswapV3Pool(tokenPosition.pool);
        (uint128 liquidity,,, uint128 tokensOwed0, uint128 tokensOwed1) = pool.positions(poolPositionKey(tokenPosition));

        if (liquidity > 0 || tokensOwed0 > 0 || tokensOwed1 > 0) {
            revert PositionNotCleared();
        }

        delete positions[tokenId];
        _burn(tokenId);
        totalSupply--;
    }

    /// @notice Callback function for Uniswap V3 mint operations.
    /// @dev Transfers the required token amounts from the payer to the pool.
    /// @param amount0 The amount of token0 required for the mint.
    /// @param amount1 The amount of token1 required for the mint.
    /// @param data Encoded callback data containing the payer and token addresses.
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata data) public {
        IUniswapV3Pool.CallbackData memory extra = abi.decode(data, (IUniswapV3Pool.CallbackData));

        IERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0);
        IERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1);
    }

    /// @notice Internal parameters for adding liquidity to a Uniswap V3 position.
    struct AddLiquidityInternalParams {
        IUniswapV3Pool pool;
        int24 lowerTick;
        int24 upperTick;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    /// @notice Adds liquidity to a Uniswap V3 position.
    /// @dev Calculates liquidity based on desired amounts and tick ranges, then mints it to the pool.
    /// @param params The parameters for adding liquidity, encapsulated in an `AddLiquidityInternalParams` struct.
    /// @return liquidity The amount of liquidity added.
    /// @return amount0 The amount of token0 used.
    /// @return amount1 The amount of token1 used.
    function _addLiquidity(AddLiquidityInternalParams memory params)
        internal
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        (uint160 sqrtPriceX96,,,,) = params.pool.slot0();

        liquidity = LiquidityMath.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(params.lowerTick),
            TickMath.getSqrtRatioAtTick(params.upperTick),
            params.amount0Desired,
            params.amount1Desired
        );

        (amount0, amount1) = params.pool.mint(
            address(this),
            params.lowerTick,
            params.upperTick,
            liquidity,
            abi.encode(
                IUniswapV3Pool.CallbackData({
                    token0: params.pool.token0(),
                    token1: params.pool.token1(),
                    payer: msg.sender
                })
            )
        );

        if (amount0 < params.amount0Min || amount1 < params.amount1Min) {
            revert SlippageCheckFailed(amount0, amount1);
        }
    }

    /// @notice Fetches the Uniswap V3 pool for the given tokens and fee tier.
    /// @dev Ensures tokens are sorted before computing the pool address.
    /// @param token0 The address of the first token.
    /// @param token1 The address of the second token.
    /// @param fee The fee tier of the pool.
    /// @return pool The address of the Uniswap V3 pool.
    function getPool(address token0, address token1, uint24 fee) internal view returns (IUniswapV3Pool pool) {
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, token0, token1, fee));
    }

    /// @notice Computes the position key within a pool.
    /// @param position The position details.
    /// @return key A unique key representing the position within the pool.
    function poolPositionKey(TokenPosition memory position) internal view returns (bytes32 key) {
        key = keccak256(abi.encodePacked(address(this), position.lowerTick, position.upperTick));
    }

    /// @notice Computes the position key within the NFT manager.
    /// @param position The position details.
    /// @return key A unique key representing the position within the NFT manager.
    function positionKey(TokenPosition memory position) internal pure returns (bytes32 key) {
        key = keccak256(abi.encodePacked(address(position.pool), position.lowerTick, position.upperTick));
    }
}
