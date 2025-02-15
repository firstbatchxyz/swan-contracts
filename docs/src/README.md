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

## Installation

First, make sure you have the requirements:

- We are using [Foundry](https://book.getfoundry.sh/), so make sure you [install](https://book.getfoundry.sh/getting-started/installation) it first.
- Upgradable contracts make use of [NodeJS](https://nodejs.org/en), so you should [install](https://nodejs.org/en/download/package-manager) that as well.

Clone the repository:

```sh
git clone git@github.com:firstbatchxyz/dria-oracle-contracts.git
```

Install dependencies with:

```sh
forge install
```

Compile the contracts with:

```sh
forge build
```

> [!NOTE]
>
> We are using [openzeppelin-foundry-upgrades](https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades) library, which [requires](https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades?tab=readme-ov-file#before-running) clean-up per compilation to ensure upgrades are done safely. We use `force = true` option in `foundry.toml` for this, which may increase build times.
>
> Note that for some users this may fail (see [issue](https://github.com/firstbatchxyz/dria-oracle-contracts/issues/16)) due to a missing NPM package called `@openzeppelin/upgrades-core`. To fix it, you can install the package manually:
>
> ```sh
> npm install @openzeppelin/upgrades-core@latest -g
> ```

### Updates

To update contracts to the latest library versions, use:

```sh
forge update
```

## Usage

### Setup

To be able to deploy & use our contracts, we need two things:

- [Ethereum Wallet](#create-wallet)
- [RPC endpoint](#prepare-rpc-endpoint)

### Create Wallet

We use keystores for wallet management, with the help of [`cast wallet`](https://book.getfoundry.sh/reference/cast/wallet-commands) command.

Use the command below to create your keystore. The command will prompt for your **private key**, and a **password** to encrypt the keystore itself.

```sh
cast wallet import <WALLET_NAME> --interactive
```

> [!ALERT]
>
> Note that you will need to enter the password when you use this keystore.

You can see your keystores under the default directory (`~/.foundry/keystores`) with the command:

```sh
cast wallet list
```

### Prepare RPC Endpoint

To interact with the blockchain, we require an RPC endpoint. You can get one from:

- [Alchemy](https://www.alchemy.com/)
- [Infura](https://www.infura.io/)
- [(see more)](https://www.alchemy.com/best/rpc-node-providers)

You will use this endpoint for the commands that interact with the blockchain, such as deploying and upgrading; or while doing fork tests.

### Deploy & Verify Contract

Deploy the contract with:

```sh
forge script ./script/Deploy.s.sol:Deploy<CONTRACT_NAME> \
--rpc-url <RPC_URL> \
--account <WALLET_NAME> \
--broadcast
```

You can see deployed contract addresses under the `deployment/<chainid>.json`

You can verify the contract during deployment by adding the verification arguments as well:

```sh
forge script ./script/Deploy.s.sol:Deploy<CONTRACT_NAME> \
--rpc-url <RPC_URL> \
--account <WALLET_NAME> \
--broadcast \
--verify --verifier blockscout \
--verifier-url <VERIFIER_URL>
```

You can verify an existing contract with:

```sh
forge verify-contract <CONTRACT_ADDRESS> ./src/<CONTRACT_NAME>.sol:<CONTRACT_NAME> \
--verifier blockscout \
--verifier-url <VERIFIER_URL>
```

Note that the `--verifier-url` value should be the target explorer's homepage URL. Some example URLs are:

- `https://base.blockscout.com/api/` for Base (Mainnet)
- `https://base-sepolia.blockscout.com/api/` for Base Sepolia (Testnet)

> [!NOTE]
>
> URL should not contain the API key! Foundry will read your `ETHERSCAN_API_KEY` from environment.

> [!NOTE]
>
> The `--verifier` can accept any of the following: `etherscan`, `blockscout`, `sourcify`, `oklink`. We are using Blockscout most of the time.

### Generate ABIs

To interact with the contracts, you need the contract ABIs. We store the ABIs under the [`abis`](./abis/) folder, and these can be generated using the following script:

```sh
./export-abis.sh
```

### Upgrade Contract

Upgrading an existing contract is done as per the instructions in [openzeppelin-foundry-upgrades](https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades) repository.
The `--sender <ADDRESS>` field is required when deploying a contract,

## Testing & Diagnostics

Run tests on local network:

```sh
forge test

# or -vvv to show reverts in detail
forge test -vvv
```

or fork an existing chain and run the tests on it:

```sh
forge test --rpc-url <RPC_URL>
```

### Code Coverage

We have a script that generates the coverage information as an HTML page. This script requires [`lcov`](https://linux.die.net/man/1/lcov) and [`genhtml`](https://linux.die.net/man/1/genhtml) command line tools. To run, do:

```sh
./coverage.sh
```

Alternatively, you can see a summarized text-only output as well:

```sh
forge coverage --no-match-coverage "(test|mock|script)"
```

### Storage Layout

You can print storage layouts for each contract using:

```sh
./storage.sh
```

The resulting Markdown files will be created under the [`storage`](./storage/) directory.

### Gas Snapshot

You can examine the gas usage metrics using the command:

```sh
forge snapshot --snap ./test/.gas-snapshot
```

You can see the snapshot `.gas-snapshot` file in the current directory.

### Styling

You can format the contracts with:

```sh
forge fmt ./src/**/*.sol ./script/**/*.sol
```

If you have solhint installed, you can lint all contracts with:

```sh
solhint 'contracts/**/*.sol'
```

## Documentation

We have auto-generated MDBook documentations under the [`docs`](./docs) folder, generated with the following command:

```sh
forge doc

# serves the book as well
forge doc --serve
```

## License

We are using [Apache-2.0](./LICENSE) license.
