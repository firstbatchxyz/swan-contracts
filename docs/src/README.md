<p align="center">
  <img src="https://raw.githubusercontent.com/firstbatchxyz/.github/refs/heads/master/branding/swan-logo-square.svg" alt="logo" width="168">
</p>

<p align="center">
  <h1 align="center">
    Swan Protocol
  </h1>
  <p align="center">
    <i>Simulated Worlds with AI Narratives.</i>
  </p>
</p>

<p align="center">
    <a href="https://opensource.org/licenses/Apache-2-0" target="_blank">
        <img alt="License: Apache 2.0" src="https://img.shields.io/badge/license-Apache_2.0-7CB9E8.svg">
    </a>
    <a href="./.github/workflows/test.yml" target="_blank">
        <img alt="Workflow: Tests" src="https://github.com/firstbatchxyz/dria-oracle-contracts/actions/workflows/test.yml/badge.svg?branch=master">
    </a>
    <a href="https://discord.gg/dria" target="_blank">
        <img alt="Discord" src="https://dcbadge.vercel.app/api/server/dria?style=flat">
    </a>
</p>

Swan is a decentralized protocol where AI agents dynamically interact with users who create artifacts inlined with agent's narratives.

## Installation

First, make sure you have the requirements:

- We are using [Foundry](https://book.getfoundry.sh/), so make sure you [install](https://book.getfoundry.sh/getting-started/installation) it first.
- Upgradable contracts make use of [NodeJS](https://nodejs.org/en), so you should [install](https://nodejs.org/en/download/package-manager) that as well.

Clone the repository:

```sh
git clone git@github.com:firstbatchxyz/swan-contracts.git
```

Install dependencies with:

```sh
forge install
```

Compile the contracts with:

```sh
forge clean && forge build
```

### Upgradability

We are using [openzeppelin-foundry-upgrades](https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades) library. To make sure upgrades are **safe**, you must do one of the following before you run `forge script` or `forge test` (as per their [docs](https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades?tab=readme-ov-file#before-running)):

- `forge clean` beforehand, e.g. `forge clean && forge test`
- include `--force` option when running, e.g. `forge test --force`

> Note that for some users this may fail (see [issue](https://github.com/firstbatchxyz/dria-oracle-contracts/issues/16)) due to a missing NPM package called `@openzeppelin/upgrades-core`. To fix it, do:
>
> ```sh
> npm install @openzeppelin/upgrades-core@latest -g
> ```

### Updates

To update contracts to the latest library versions, use:

```sh
forge update
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
forge clean && forge script ./script/Deploy.s.sol:Deploy<CONTRACT_NAME> --rpc-url <RPC_URL> --account <FILE_NAME_OF_YOUR_KEYSTORE> --sender <DEPLOYER_ADDRESS> --broadcast --verify --verifier <etherscan|blockscout|sourcify> --verifier-url <VERIFIER_URL>
```

> [!NOTE] > `<VERIFIER_URL>` should be expolorer's homepage url. Forge reads your `<ETHERSCAN_API_KEY>` from .env file so you don't need to add this at the end of `<VERIFIER_URL>`.
>
> e.g.
> `https://base-sepolia.blockscout.com/api/` for `Base Sepolia Network`

You can see deployed contract addresses under the `deployment/<chainid>.json`

## Verify Contract

Verify contract manually with:

```sh
forge verify-contract <CONTRACT_ADDRESS> src/$<CONTRACT_NAME>.sol:<CONTRACT_NAME> --verifier <etherscan|blockscout|sourcify> --verifier-url <VERIFIER_URL>
```

## Testing & Diagnostics

Run tests on local network:

```sh
forge clean && forge test
```

or fork an existing chain and run the tests on it:

```sh
forge clean && forge test --rpc-url <RPC_URL>
```

### Coverage

Check coverages with:

```sh
forge clean && bash coverage.sh
```

or to see summarized coverages on terminal:

```sh
forge clean && forge coverage --no-match-coverage "(test|mock|script)"
```

You can see coverages under the coverage directory.

### Storage Layout

Get storage layout with:

```sh
forge clean && bash storage.sh
```

You can see storage layouts under the storage directory.

### Gas Snapshot

Take the gas snapshot with:

```sh
forge clean && forge snapshot
```

You can see the snapshot `.gas-snapshot` file in the current directory.

## Documentation

We have auto-generated documentation under the [`docs`](./docs) folder, generated with the following command:

```sh
forge doc
```

We provide an MDBook template over it, which you can open via:

```sh
cd docs && mdbook serve --open
```

## License

We are using Apache-2.0 license.
