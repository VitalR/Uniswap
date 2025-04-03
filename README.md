# Uniswap (V3 Clone for Educational Purposes)

> ⚠️ **Disclaimer**: This is an unofficial educational clone of the Uniswap V3 protocol, created for research and experimentation.
It is not affiliated with or endorsed by Uniswap Labs or the Uniswap Foundation.
Not intended for production use.

A simplified Uniswap V3 implementation focused on core concepts like pool creation, swaps, liquidity provision, and quoting. Ideal for developers exploring how Uniswap V3 works under the hood.

## 🧠 Learning Resources & References

- 📘 [Uniswap V2 Whitepaper](https://uniswap.org/whitepaper.pdf)  
- 📚 [Programming DeFi (by Jeiwan)](https://jeiwan.net/posts/programming-defi-uniswapv2-1/)  
- 📖 [Uniswap V3 Book (Highly Recommended)](https://uniswapv3book.com/index.html)  
  > A huge thanks to [Uniswap V3 Book](https://uniswapv3book.com/index.html) for providing clear explanations and visuals for the V3 architecture and math.

## 📁 Project Structure

src/    
├── UniswapV3Factory.sol # Pool factory \
        ├── UniswapV3Manager.sol # Handles minting and swaps \
        ├── UniswapV3Pool.sol # Core pool logic (ticks, liquidity, swaps) \
        ├── UniswapV3Quoter.sol # Quote estimation without executing swaps \
        ├── UniswapV3NFTManager.sol # (Optional) Position management 

test/   
├── fixtures/ # Setup scenarios and token pairs \
        ├── libraries/ # Unit tests for TickMath, Path, etc. \
        ├── mocks/ # Mock ERC20s and helper contracts \
        ├── utils/ # Assertion helpers and testing utils


scripts/

└── UniswapV3Deployer.s.sol # Deployment script using Foundry (forge)


## 🛠️ Tech Stack

- **Solidity** `^0.8.29`
- **Foundry** for development and testing
- **Anvil** for local forked EVM

## ⚙️ Usage

```bash
# Compile & deploy locally
make deploy-local
```
This will:

- Spin up a local Anvil node (if not already running)

- Deploy mock tokens, Uniswap core contracts (factory, pools, manager, quoter)

- Initialize multiple pools

- Add initial liquidity to each pool

## 📄 License
MIT © 2025 \
Built for fun, learning, and DeFi exploration 🚀