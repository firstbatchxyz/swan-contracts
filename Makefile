-include .env

.PHONY: build test local-key base-sepolia-key deploy anvil install update doc

# Capture the network name
network := $(word 2, $(MAKECMDGOALS))

# Default to forked base-sepolia network
KEY_NAME := local-key
NETWORK_ARGS := --account local-key --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --broadcast

ifeq ($(network), base-sepolia)
KEY_NAME := base-sepolia-key 
NETWORK_ARGS:= --rpc-url $(BASE_TEST_RPC_URL) --account base-sepolia-key --sender $(PUBLIC_KEY) --broadcast --verify --verifier blockscout --verifier-url https://base-sepolia.blockscout.com/api/
endif

# Install Dependencies
install:
	forge install foundry-rs/forge-std --no-commit && forge install firstbatchxyz/dria-oracle-contracts --no-commit && forge install OpenZeppelin/openzeppelin-contracts --no-commit && forge install OpenZeppelin/openzeppelin-foundry-upgrades --no-commit && forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit

# Build the contracts
build:
	forge clean && forge build

# Generate gas snapshot under snapshots directory
snapshot:
	forge snapshot

# Test the contracts on forked base-sepolia network
test:
	forge clean && forge test --fork-url $(BASE_TEST_RPC_URL)

anvil:
	anvil --fork-url $(BASE_TEST_RPC_URL)

# Create keystores for encrypted private keys by using bls12-381 curve (https://eips.ethereum.org/EIPS/eip-2335)
key:
	cast wallet import $(KEY_NAME) --interactive

# Default to local network if no network is specified
deploy:
	forge script ./script/Deploy.s.sol:Deploy $(NETWORK_ARGS)

# Generate contract documentation under docs dir. You can also see the docs on http://localhost:4000
doc:
	forge doc

# TODO: forge-verify

# Prevent make from interpreting the network name as a target
$(eval $(network):;@:)