// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "../lib/forge-std/src/Script.sol";
import "../lib/forge-std/src/console2.sol";
import "../lib/forge-std/src/Vm.sol";

import { IUniswapV3Manager } from "../src/interfaces/IUniswapV3Manager.sol";
import { FixedPoint96 } from "../src/libraries/FixedPoint96.sol";
import { Math } from "../src/libraries/Math.sol";
import { UniswapV3Factory } from "../src/UniswapV3Factory.sol";
import { UniswapV3Manager } from "../src/UniswapV3Manager.sol";
import { UniswapV3Pool } from "../src/UniswapV3Pool.sol";
import { UniswapV3Quoter } from "../src/UniswapV3Quoter.sol";
import { ERC20Mock } from "../test/mocks/ERC20Mock.sol";
import { TestUtils } from "../test/utils/TestUtils.sol";

contract UniswapV3Deployer is Script, TestUtils {
    struct TokenConfig {
        string name;
        string symbol;
        uint8 decimals;
        uint256 initialSupply;
        uint256 approvalAmount;
    }

    struct PoolConfig {
        address token0;
        address token1;
        uint24 fee;
        uint256 initialPrice;
        uint256 amount0;
        uint256 amount1;
        uint256 lowerPrice;
        uint256 upperPrice;
    }

    // Token configurations
    TokenConfig internal wethConfig;
    TokenConfig internal usdcConfig;
    TokenConfig internal uniConfig;
    TokenConfig internal wbtcConfig;
    TokenConfig internal usdtConfig;

    // Pool configurations
    PoolConfig[4] internal poolConfigs;

    // Deployed contracts
    struct DeployedContracts {
        ERC20Mock weth;
        ERC20Mock usdc;
        ERC20Mock uni;
        ERC20Mock wbtc;
        ERC20Mock usdt;
        UniswapV3Factory factory;
        UniswapV3Manager manager;
        UniswapV3Quoter quoter;
        address[] poolAddresses;
    }

    // Instance variables for contracts needed across functions
    UniswapV3Factory internal factory;
    UniswapV3Manager internal manager;

    constructor() {
        // Initialize token configurations with reasonable values
        wethConfig = TokenConfig({
            name: "Wrapped Ether",
            symbol: "WETH",
            decimals: 18,
            initialSupply: 1000 ether,  // Reduced from 10M
            approvalAmount: 1000 ether  // Reduced from 10M
        });
        
        usdcConfig = TokenConfig({
            name: "USD Coin",
            symbol: "USDC",
            decimals: 6,  // Changed to actual USDC decimals
            initialSupply: 5000000 * 10**6,  // 5M USDC
            approvalAmount: 5000000 * 10**6
        });
        
        uniConfig = TokenConfig({
            name: "Uniswap Coin",
            symbol: "UNI",
            decimals: 18,
            initialSupply: 1000 ether,  // Reduced from 10M
            approvalAmount: 1000 ether
        });
        
        wbtcConfig = TokenConfig({
            name: "Wrapped Bitcoin",
            symbol: "WBTC",
            decimals: 8,  // Changed to actual WBTC decimals
            initialSupply: 100 * 10**8,  // 100 WBTC
            approvalAmount: 100 * 10**8
        });
        
        usdtConfig = TokenConfig({
            name: "USD Token",
            symbol: "USDT",
            decimals: 6,  // Changed to actual USDT decimals
            initialSupply: 5000000 * 10**6,  // 5M USDT
            approvalAmount: 5000000 * 10**6
        });
    }

    function setUp() public {
        // No setup needed - we'll configure pools in run()
    }

    function deployToken(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply,
        address recipient,
        address spender,
        uint256 approvalAmount
    ) internal returns (ERC20Mock) {
        ERC20Mock token = new ERC20Mock(name, symbol);
        token.mint(recipient, initialSupply);
        
        console2.log("Minted tokens");
        
        if (spender != address(0) && approvalAmount > 0) {
            token.approve(spender, approvalAmount);
            console2.log("Approved tokens");
        }
        
        return token;
    }

    function run() public {
        DeployedContracts memory deployed;
        deployed.poolAddresses = new address[](4);
        
        // Start deployment transaction
        vm.startBroadcast();
        
        address deployer = msg.sender;
        console2.log("Deployer address");

        // Deploy core contracts first
        deployed.factory = new UniswapV3Factory();
        deployed.manager = new UniswapV3Manager(address(deployed.factory));
        deployed.quoter = new UniswapV3Quoter(address(deployed.factory));
        
        // Store references for use in helper functions
        factory = deployed.factory;
        manager = deployed.manager;
        
        console2.log("Factory deployed");
        console2.log("Manager deployed");
        console2.log("Quoter deployed");

        // Deploy tokens with appropriate balances
        deployed.weth = deployToken(
            wethConfig.name,
            wethConfig.symbol,
            wethConfig.decimals,
            wethConfig.initialSupply,
            deployer,
            address(deployed.manager),
            wethConfig.approvalAmount
        );
        
        deployed.usdc = deployToken(
            usdcConfig.name,
            usdcConfig.symbol,
            usdcConfig.decimals,
            usdcConfig.initialSupply,
            deployer,
            address(deployed.manager),
            usdcConfig.approvalAmount
        );
        
        deployed.uni = deployToken(
            uniConfig.name,
            uniConfig.symbol,
            uniConfig.decimals,
            uniConfig.initialSupply,
            deployer,
            address(deployed.manager),
            uniConfig.approvalAmount
        );
        
        deployed.wbtc = deployToken(
            wbtcConfig.name,
            wbtcConfig.symbol,
            wbtcConfig.decimals,
            wbtcConfig.initialSupply,
            deployer,
            address(deployed.manager),
            wbtcConfig.approvalAmount
        );
        
        deployed.usdt = deployToken(
            usdtConfig.name,
            usdtConfig.symbol,
            usdtConfig.decimals,
            usdtConfig.initialSupply,
            deployer,
            address(deployed.manager),
            usdtConfig.approvalAmount
        );

        // Log token addresses
        console2.log("All tokens deployed");

        // ----- WETH-USDC pool -----
        console2.log("Deploying WETH-USDC pool");
        
        // Create WETH-USDC pool (ensure tokens are in the correct order)
        address token0 = address(deployed.weth);
        address token1 = address(deployed.usdc);
        
        // Ensure token0 < token1 as required by Uniswap V3
        if (token0 > token1) {
            address temp = token0;
            token0 = token1;
            token1 = temp;
        }
        
        // Calculate ticks for price range 4545-5500
        int24 lowerTick = tick60(4545);
        int24 upperTick = tick60(5500);
        
        // Deploy WETH-USDC pool with fee 0.3%
        address wethUsdcPool = deployPool(token0, token1, 3000, 5000);
        deployed.poolAddresses[0] = wethUsdcPool;
        console2.log("WETH-USDC pool deployed");
        
        // Add liquidity to WETH-USDC pool (use smaller amounts)
        console2.log("Adding liquidity to WETH-USDC pool");
        
        uint256 weth_amount = 5 ether;        // 5 WETH
        uint256 usdc_amount = 25000 * 10**6;  // 25,000 USDC
        
        // If tokens were swapped for correct ordering, swap amounts too
        if (token0 == address(deployed.usdc)) {
            addLiquidity(
                token0,
                token1,
                3000,
                lowerTick,
                upperTick,
                usdc_amount,
                weth_amount
            );
        } else {
            addLiquidity(
                token0,
                token1,
                3000,
                lowerTick,
                upperTick,
                weth_amount,
                usdc_amount
            );
        }
        
        console2.log("Added liquidity to WETH-USDC pool");
        
        // ----- WETH-UNI pool -----
        console2.log("Deploying WETH-UNI pool");
        
        // Create WETH-UNI pool (ensure tokens are in the correct order)
        token0 = address(deployed.weth);
        token1 = address(deployed.uni);
        
        // Ensure token0 < token1 as required by Uniswap V3
        if (token0 > token1) {
            address temp = token0;
            token0 = token1;
            token1 = temp;
        }
        
        // Calculate ticks for price range 7-13
        lowerTick = tick60(7);
        upperTick = tick60(13);
        
        // Deploy WETH-UNI pool with fee 0.3%
        address wethUniPool = deployPool(token0, token1, 3000, 10);
        deployed.poolAddresses[1] = wethUniPool;
        console2.log("WETH-UNI pool deployed");
        
        // Add liquidity to WETH-UNI pool (use smaller amounts)
        console2.log("Adding liquidity to WETH-UNI pool");
        
        weth_amount = 5 ether;     // 5 WETH
        uint256 uni_amount = 50 ether;  // 50 UNI
        
        // If tokens were swapped for correct ordering, swap amounts too
        if (token0 == address(deployed.uni)) {
            addLiquidity(
                token0,
                token1,
                3000,
                lowerTick,
                upperTick,
                uni_amount,
                weth_amount
            );
        } else {
            addLiquidity(
                token0,
                token1,
                3000,
                lowerTick,
                upperTick,
                weth_amount,
                uni_amount
            );
        }
        
        console2.log("Added liquidity to WETH-UNI pool");
        
        // ----- WBTC-USDT pool -----
        console2.log("Deploying WBTC-USDT pool");
        
        // Create WBTC-USDT pool (ensure tokens are in the correct order)
        token0 = address(deployed.wbtc);
        token1 = address(deployed.usdt);
        
        // Ensure token0 < token1 as required by Uniswap V3
        if (token0 > token1) {
            address temp = token0;
            token0 = token1;
            token1 = temp;
        }
        
        // Calculate ticks for price range 19400-20500
        lowerTick = tick60(19400);
        upperTick = tick60(20500);
        
        // Deploy WBTC-USDT pool with fee 0.3%
        address wbtcUsdtPool = deployPool(token0, token1, 3000, 20000);
        deployed.poolAddresses[2] = wbtcUsdtPool;
        console2.log("WBTC-USDT pool deployed");
        
        // Add liquidity to WBTC-USDT pool (use smaller amounts)
        console2.log("Adding liquidity to WBTC-USDT pool");
        
        uint256 wbtc_amount = 1 * 10**8;      // 1 WBTC
        uint256 usdt_amount = 20000 * 10**6;  // 20,000 USDT
        
        // If tokens were swapped for correct ordering, swap amounts too
        if (token0 == address(deployed.usdt)) {
            addLiquidity(
                token0,
                token1,
                3000,
                lowerTick,
                upperTick,
                usdt_amount,
                wbtc_amount
            );
        } else {
            addLiquidity(
                token0,
                token1,
                3000,
                lowerTick,
                upperTick,
                wbtc_amount,
                usdt_amount
            );
        }
        
        console2.log("Added liquidity to WBTC-USDT pool");
        
        // ----- USDT-USDC pool -----
        console2.log("Deploying USDT-USDC pool");
        
        // Create USDT-USDC pool (ensure tokens are in the correct order)
        token0 = address(deployed.usdt);
        token1 = address(deployed.usdc);
        
        // Ensure token0 < token1 as required by Uniswap V3
        if (token0 > token1) {
            address temp = token0;
            token0 = token1;
            token1 = temp;
        }
        
        // Hard-coded ticks for 0.95-1.05 price range with 10 tick spacing (for 500 fee tier)
        lowerTick = -500; // Approximates 0.95
        upperTick = 500;  // Approximates 1.05
        
        // Adjust to nearest usable tick with 10 spacing
        lowerTick = nearestUsableTick(lowerTick, 10);
        upperTick = nearestUsableTick(upperTick, 10);
        
        // Deploy USDT-USDC pool with fee 0.05%
        address usdtUsdcPool = deployPool(token0, token1, 500, 1);
        deployed.poolAddresses[3] = usdtUsdcPool;
        console2.log("USDT-USDC pool deployed");
        
        // Add liquidity to USDT-USDC pool (use smaller amounts)
        console2.log("Adding liquidity to USDT-USDC pool");
        
        usdt_amount = 50000 * 10**6;  // 50,000 USDT
        usdc_amount = 50000 * 10**6;  // 50,000 USDC
        
        // If tokens were swapped for correct ordering, swap amounts too
        if (token0 == address(deployed.usdc)) {
            addLiquidity(
                token0,
                token1,
                500,
                lowerTick,
                upperTick,
                usdc_amount,
                usdt_amount
            );
        } else {
            addLiquidity(
                token0,
                token1,
                500,
                lowerTick,
                upperTick,
                usdt_amount,
                usdc_amount
            );
        }
        
        console2.log("Added liquidity to USDT-USDC pool");

        vm.stopBroadcast();

        // Log deployment results
        logDeployment(deployed);
    }

    // Helper function to deploy a pool
    function deployPool(
        address token0,
        address token1,
        uint24 fee,
        uint256 initialPriceX96
    ) internal returns (address) {
        // Create pool
        UniswapV3Pool pool = UniswapV3Pool(factory.createPool(token0, token1, fee));
        console2.log("Pool created");
        
        // Initialize pool with price
        uint160 sqrtPriceX96 = sqrtP(initialPriceX96);
        pool.initialize(sqrtPriceX96);
        console2.log("Pool initialized");
        
        return address(pool);
    }
    
    // Helper function to add liquidity to a pool
    function addLiquidity(
        address token0,
        address token1,
        uint24 fee,
        int24 lowerTick,
        int24 upperTick,
        uint256 amount0,
        uint256 amount1
    ) internal {
        IUniswapV3Manager.MintParams memory params = IUniswapV3Manager.MintParams({
            tokenA: token0,
            tokenB: token1,
            fee: fee,
            lowerTick: lowerTick,
            upperTick: upperTick,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0
        });
        
        manager.mint(params);
    }

    function logDeployment(DeployedContracts memory deployed) internal view {
        console2.log("=== Deployment Results ===");
        
        console2.log("Token Addresses:");
        console2.log("WETH deployed");
        console2.log("USDC deployed");
        console2.log("UNI deployed");
        console2.log("WBTC deployed");
        console2.log("USDT deployed");
        
        console2.log("Core Contract Addresses:");
        console2.log("Factory deployed");
        console2.log("Manager deployed");
        console2.log("Quoter deployed");
        
        console2.log("Pool Addresses:");
        for (uint i = 0; i < deployed.poolAddresses.length; i++) {
            address poolAddress = deployed.poolAddresses[i];
            if (poolAddress != address(0)) {
                console2.log("Pool deployed");
            } else {
                console2.log("Pool not deployed");
            }
        }
    }
}