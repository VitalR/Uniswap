# include .env file and export its env vars
# (-include to ignore error if it does not exist)
# include .env

.PHONY: all build test deploy clean format lint anvil

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
DEPLOY_URL := http://localhost:8545

# Default target
all: build test

# Build the project
build:
	forge build

# Run tests
test:
	forge test -vvv

# Run tests with coverage
coverage:
	forge coverage
	forge coverage --report

# Start anvil local node
anvil:
	@echo "Starting anvil local node..."
	@if lsof -Pi :8545 -sTCP:LISTEN -t >/dev/null ; then \
		echo "Anvil is already running" ; \
	else \
		anvil --chain-id 1337 > /dev/null 2>&1 & \
		echo "Anvil started with chain ID 1337" ; \
		sleep 2 ; \
	fi

# Deploy to local network
deploy-local: build
	@echo "Checking if Anvil is running..."
	@if ! lsof -Pi :8545 -sTCP:LISTEN -t >/dev/null ; then \
		echo "Starting Anvil..." ; \
		anvil --chain-id 1337 --code-size-limit 999999 > /dev/null 2>&1 & \
		echo "Waiting for Anvil to start..." ; \
		sleep 2 ; \
	fi
	@echo "Deploying to local network..."
	forge script scripts/UniswapV3Deployer.s.sol:UniswapV3Deployer --rpc-url ${DEPLOY_URL} --broadcast --private-key ${DEFAULT_ANVIL_KEY} --skip-simulation --force -vvvv

# Stop anvil local node
stop-anvil:
	@echo "Stopping anvil local node..."
	@if lsof -Pi :8545 -sTCP:LISTEN -t >/dev/null ; then \
		kill $$(lsof -Pi :8545 -sTCP:LISTEN -t) ; \
		echo "Anvil stopped" ; \
	else \
		echo "No Anvil instance running" ; \
	fi

# Deploy to testnet
deploy-testnet: build
	forge script scripts/UniswapV3Deployer.s.sol:UniswapV3Deployer --rpc-url testnet --broadcast

# Deploy to mainnet
deploy-mainnet: build
	forge script scripts/UniswapV3Deployer.s.sol:UniswapV3Deployer --rpc-url mainnet --broadcast

# Clean build artifacts
clean:
	forge clean

# Format code
format:
	forge fmt

# Run linter
lint:
	forge fmt --check
	forge build --force

# Install dependencies
install:
	forge install

# Update dependencies
update:
	forge update

# Generate documentation
doc:
	forge doc

# Run gas report
gas-report:
	forge test --gas-report

# Run slither analysis
slither:
	slither .

# Run mythril analysis
mythril:
	myth analyze src/*.sol

# Run all security checks
security: slither mythril

# Help command
help:
	@echo "Available commands:"
	@echo "  make build         - Build the project"
	@echo "  make test          - Run tests"
	@echo "  make coverage      - Run tests with coverage"
	@echo "  make anvil         - Start anvil local node"
	@echo "  make stop-anvil    - Stop anvil local node"
	@echo "  make deploy-local  - Deploy to local network (starts anvil if not running)"
	@echo "  make deploy-testnet - Deploy to testnet"
	@echo "  make deploy-mainnet - Deploy to mainnet"
	@echo "  make clean         - Clean build artifacts"
	@echo "  make format        - Format code"
	@echo "  make lint          - Run linter"
	@echo "  make install       - Install dependencies"
	@echo "  make update        - Update dependencies"
	@echo "  make doc           - Generate documentation"
	@echo "  make gas-report    - Run gas report"
	@echo "  make security      - Run security checks"
	@echo "  make help          - Show this help message" 