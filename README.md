# Swan Protocol
Swan is a **Decentralized Protocol** where AI agents (buyers) dynamically interact with asset creators. Agents operate with budgets to purchase assets that match their objectives. Asset creators design assets to align with buyers’ needs to convince the LLM to buy their asset/assets.

## Compile

Compile the contracts with:

```sh
forge clean && forge build
```

> [!NOTE]
>
> Openzeppelin' foundry modules expect that running `forge clean` before running Foundry script or test or include `--force` option when running `forge script` or `forge test`.

## Test

Run tests on local:

```sh
forge clean && forge test
```

or on any other evm chain:

```sh
forge clean && forge test --rpc-url <RPC_URL>
```

## Deployment

**Step 1.**
Import your `ETHERSCAN_API_KEY` to env file.

> [!NOTE]
>
> Foundry expects the API key to be defined as `ETHERSCAN_API_KEY` even though you're using another explorer.

**Step 2.**
Create keystores for deployment. [See more for keystores](https://eips.ethereum.org/EIPS/eip-2335)

```sh
cast wallet import <FILE_NAME_OF_YOUR_KEYSTORE> --interactive
```
You can see your wallets with:

```sh
cast wallet list
```

> [!NOTE]
>
> Recommended to create keystores on directly on your shell.
> You HAVE to type your password on the terminal to be able to use your keys. (e.g when deploying a contract)

**Step 3.**
Enter your private key (associated with your address) and password on terminal. You'll see your address on terminal.

> [!NOTE]
>
> If you want to deploy contracts on localhost please provide local address for the command above.

**Step 4.**
Deploy the contract with:

```sh
forge clean && forge script ./script/Deploy.s.sol:Deploy<CONTRACT_NAME> --rpc-url <RPC_URL> --account <FILE_NAME_OF_YOUR_KEYSTORE> --sender <DEPLOYER_ADDRESS> --broadcast
```
or for instant verification use:

```sh
forge clean && forge script ./script/Deploy.s.sol:Deploy --rpc-url <RPC_URL> --account <FILE_NAME_OF_YOUR_KEYSTORE> --sender <DEPLOYER_ADDRESS> --broadcast --verify --verifier <etherscan|blockscout|sourcify> --verifier-url <VERIFIER_URL>
```

> [!NOTE]
> `<VERIFIER_URL>` should be expolorer's homepage url. Forge reads your `<ETHERSCAN_API_KEY>` from .env file so you don't need to add this at the end of `<VERIFIER_URL>`.
>
> e.g. 
> `https://base-sepolia.blockscout.com/api/` for `Base Sepolia Network`
>

You can see deployed contract addresses under the `deployment/<chainid>.json`

## Verify Contract

Verify contract manually with:

```sh
forge verify-contract <CONTRACT_ADDRESS> src/$<CONTRACT_NAME>.sol:<CONTRACT_NAME> --verifier <etherscan|blockscout|sourcify> --verifier-url <VERIFIER_URL>
```

## Coverage

Check coverages with:

```sh
forge clean && bash coverage.sh
```
or to see summarized coverages on terminal:

```sh
forge clean && forge coverage --no-match-coverage "(test|mock|script)"
```

You can see coverages under the coverage directory.

## Storage Layout

Get storage layout with:

```sh
forge clean && bash storage.sh
```

You can see storage layouts under the storage directory.

## Gas Snapshot

Take the gas snapshot with:

```sh
forge clean && forge snapshot
```

You can see the snapshot `.gas-snapshot` file in the current directory.

## Format

Format code with:

```sh
forge fmt
```

## Generate documentation

Generate documentation with:

```sh
forge doc
```

## Update

Update modules with:

```sh
forge update
```

You can see the documentation under the `docs/` directory.
