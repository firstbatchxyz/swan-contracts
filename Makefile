-include .env

.PHONY: build test local-key base-sepolia-key deploy update

# Capture the network name
network := $(word 2, $(MAKECMDGOALS))
contractAddress := $(word 3, $(MAKECMDGOALS))
contractName := $(word 4, $(MAKECMDGOALS))

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

# Update modules
update:
	forge update

# Build the contracts
build:
	forge clean && forge build

# Generate gas snapshot
snapshot:
	forge snapshot

# Test the contracts forked base-sepolia network with 4 parallel jobs
test:
	forge clean && forge test --fork-url $(BASE_TEST_RPC_URL) --no-match-contract "InvariantTest" --jobs 4

# Run invariant tests on local network with 4 parallel jobs
test-inv:
	forge clean && forge test --match-contract "InvariantTest" --jobs 4

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

# Format code
fmt:
	forge fmt

# Coverage
cov:
	forge clean && forge coverage --no-match-coverage "(test|mock|script)" --jobs 4

# Verify contract on blockscout
verify:
	forge verify-contract $(contractAddress) src/$(contractName).sol:$(contractName) --verifier blockscout --verifier-url https://base-sepolia.blockscout.com/api/

# Prevent make from interpreting params as a target
$(eval $(network):;@:)
$(eval $(contractAddress):;@:)
$(eval $(contractName):;@:)