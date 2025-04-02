// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Script.sol";

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
        // Initialize token configurations with higher supplies and approvals
        wethConfig = TokenConfig({
            name: "Wrapped Ether",
            symbol: "WETH",
            decimals: 18,
            initialSupply: 10000 ether,
            approvalAmount: 10000 ether
        });
        
        usdcConfig = TokenConfig({
            name: "USD Coin",
            symbol: "USDC",
            decimals: 18,
            initialSupply: 50_000_000 ether,
            approvalAmount: 50_000_000 ether
        });
        
        uniConfig = TokenConfig({
            name: "Uniswap Coin",
            symbol: "UNI",
            decimals: 18,
            initialSupply: 10000 ether,
            approvalAmount: 10000 ether
        });
        
        wbtcConfig = TokenConfig({
            name: "Wrapped Bitcoin",
            symbol: "WBTC",
            decimals: 18,
            initialSupply: 10000 ether,
            approvalAmount: 10000 ether
        });
        
        usdtConfig = TokenConfig({
            name: "USD Token",
            symbol: "USDT",
            decimals: 18,
            initialSupply: 50_000_000 ether,
            approvalAmount: 50_000_000 ether
        });
    }

    function setUp() public {
        // No setup needed - we'll configure pools in run()
    }

    function deployToken(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address recipient,
        address spender,
        uint256 approvalAmount
    ) internal returns (ERC20Mock) {
        ERC20Mock token = new ERC20Mock(name, symbol);
        token.mint(recipient, initialSupply);
        
        // No logging to avoid console issues
        
        if (spender != address(0) && approvalAmount > 0) {
            token.approve(spender, approvalAmount);
        }
        
        return token;
    }

    function run() public {
        DeployedContracts memory deployed;
        deployed.poolAddresses = new address[](4);
        
        // Start deployment transaction
        vm.startBroadcast();
        
        address deployer = msg.sender;

        // Deploy core contracts first
        deployed.factory = new UniswapV3Factory();
        deployed.manager = new UniswapV3Manager(address(deployed.factory));
        deployed.quoter = new UniswapV3Quoter(address(deployed.factory));
        
        // Store references for use in helper functions
        factory = deployed.factory;
        manager = deployed.manager;

        // Deploy tokens with higher balances
        deployed.weth = deployToken(
            "Wrapped Ether", 
            "WETH", 
            10_000_000 ether, 
            deployer, 
            address(deployed.manager), 
            10_000_000 ether
        );
        
        deployed.usdc = deployToken(
            "USD Coin", 
            "USDC", 
            50_000_000_000 ether, 
            deployer, 
            address(deployed.manager), 
            50_000_000_000 ether
        );
        
        deployed.uni = deployToken(
            "Uniswap Coin", 
            "UNI", 
            10_000_000 ether, 
            deployer, 
            address(deployed.manager), 
            10_000_000 ether
        );
        
        deployed.wbtc = deployToken(
            "Wrapped Bitcoin", 
            "WBTC", 
            10_000_000 ether, 
            deployer, 
            address(deployed.manager), 
            10_000_000 ether
        );
        
        deployed.usdt = deployToken(
            "USD Token", 
            "USDT", 
            50_000_000_000 ether, 
            deployer, 
            address(deployed.manager), 
            50_000_000_000 ether
        );

        // ----- WETH-USDC pool -----
        address token0 = address(deployed.weth);
        address token1 = address(deployed.usdc);
        
        // Calculate ticks for price range 4545-5500
        int24 lowerTick = tick60(4545);
        int24 upperTick = tick60(5500);
        
        // Deploy WETH-USDC pool
        address wethUsdcPool = deployPool(token0, token1, 3000, 5000);
        deployed.poolAddresses[0] = wethUsdcPool;
        
        // Add liquidity to WETH-USDC pool
        addLiquidity(
            token0,
            token1,
            3000,
            lowerTick,
            upperTick,
            10 ether,          // 10 WETH
            50000 ether        // 50,000 USDC
        );
        
        // ----- WETH-UNI pool -----
        token0 = address(deployed.weth);
        token1 = address(deployed.uni);
        
        // Calculate ticks for price range 7-13
        lowerTick = tick60(7);
        upperTick = tick60(13);
        
        // Deploy WETH-UNI pool
        address wethUniPool = deployPool(token0, token1, 3000, 10);
        deployed.poolAddresses[1] = wethUniPool;
        
        // Add liquidity to WETH-UNI pool
        addLiquidity(
            token0,
            token1,
            3000,
            lowerTick,
            upperTick,
            10 ether,          // 10 WETH
            100 ether          // 100 UNI
        );
        
        // ----- WBTC-USDT pool -----
        token0 = address(deployed.wbtc);
        token1 = address(deployed.usdt);
        
        // Calculate ticks for price range 19400-20500
        lowerTick = tick60(19400);
        upperTick = tick60(20500);
        
        // Deploy WBTC-USDT pool
        address wbtcUsdtPool = deployPool(token0, token1, 3000, 20000);
        deployed.poolAddresses[2] = wbtcUsdtPool;
        
        // Add liquidity to WBTC-USDT pool
        addLiquidity(
            token0,
            token1,
            3000,
            lowerTick,
            upperTick,
            1 ether,           // 1 WBTC
            20000 ether        // 20,000 USDT
        );
        
        // ----- USDT-USDC pool -----
        token0 = address(deployed.usdt);
        token1 = address(deployed.usdc);
        
        // Hard-coded ticks for 0.95-1.05 price range with 10 tick spacing (for 500 fee tier)
        lowerTick = -500; // Approximates 0.95
        upperTick = 500;  // Approximates 1.05
        
        // Adjust to nearest usable tick with 10 spacing
        lowerTick = nearestUsableTick(lowerTick, 10);
        upperTick = nearestUsableTick(upperTick, 10);
        
        // Deploy USDT-USDC pool
        address usdtUsdcPool = deployPool(token0, token1, 500, 1);
        deployed.poolAddresses[3] = usdtUsdcPool;
        
        // Add liquidity to USDT-USDC pool
        addLiquidity(
            token0,
            token1,
            500,
            lowerTick,
            upperTick,
            100_000 ether,     // 100,000 USDT
            100_000 ether      // 100,000 USDC
        );

        vm.stopBroadcast();
        
        // Report deployment information via emit events
        emit TokenDeployed("WETH", address(deployed.weth));
        emit TokenDeployed("USDC", address(deployed.usdc));
        emit TokenDeployed("UNI", address(deployed.uni));
        emit TokenDeployed("WBTC", address(deployed.wbtc));
        emit TokenDeployed("USDT", address(deployed.usdt));
        
        emit CoreContractDeployed("Factory", address(deployed.factory));
        emit CoreContractDeployed("Manager", address(deployed.manager));
        emit CoreContractDeployed("Quoter", address(deployed.quoter));
        
        emit PoolDeployed("WETH-USDC", deployed.poolAddresses[0]);
        emit PoolDeployed("WETH-UNI", deployed.poolAddresses[1]);
        emit PoolDeployed("WBTC-USDT", deployed.poolAddresses[2]);
        emit PoolDeployed("USDT-USDC", deployed.poolAddresses[3]);
    }
    
    // Events to provide deployment info
    event TokenDeployed(string indexed name, address tokenAddress);
    event CoreContractDeployed(string indexed name, address contractAddress);
    event PoolDeployed(string indexed name, address poolAddress);

    // Helper function to deploy a pool
    function deployPool(
        address token0,
        address token1,
        uint24 fee,
        uint256 initialPriceX96
    ) internal returns (address) {
        // Create pool
        UniswapV3Pool pool = UniswapV3Pool(factory.createPool(token0, token1, fee));
        
        // Initialize pool with price
        uint160 sqrtPriceX96 = sqrtP(initialPriceX96);
        pool.initialize(sqrtPriceX96);
        
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
}