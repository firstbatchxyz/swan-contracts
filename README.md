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

> [!TIP]
>
> If at any point the submodules become "dirty" (e.g. there are local changes that you are unaware of) you can do:
>
> ```sh
> git submodule deinit -f .
> git submodule update --init --recursive --checkout
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

### Deploy Contract

Deploy the contract with:

```sh
forge script ./script/Deploy.s.sol:Deploy<CONTRACT_NAME> \
--rpc-url <RPC_URL> \
--account <WALLET_NAME> \
--broadcast
```

You can see deployed contract addresses under the [`deployments/<chainid>.json`](./deployments/) folder.

You will need the contract ABIs to interact with them as well, thankfully there is a nice short-hand command to export that:

```sh
forge inspect <CONTRACT_NAME> abi > ./deployments/abis/<CONTRACT_NAME>.json
```

### Verify Contract

Verification requires the following values, based on which provider you are using:

- **Provider**: can accept any of `etherscan`, `blockscout`, `sourcify`, `oklink` or `custom` for more fine-grained stuff.
- **URL**: based on the chosen provider, we require its URL as well, e.g. `https://base-sepolia.blockscout.com/api/` for `blockscout` on Base Sepolia
- **API Key**: an API key from the chosen provider, must be stored as `ETHERSCAN_API_KEY` in environment no matter whicih provider it is!.

You can actually verify the contract during deployment by adding the verification arguments as well:

```sh
forge script ./script/Deploy.s.sol:Deploy<CONTRACT_NAME> \
--rpc-url <RPC_URL> \
--account <WALLET_NAME> \
--broadcast \
--verify --verifier blockscout \
--verifier-url <VERIFIER_URL>
```

Alternatively, you can verify an existing contract (perhaps deployed from a factory) with:

```sh
forge verify-contract <CONTRACT_ADDRESS> ./src/<CONTRACT_NAME>.sol:<CONTRACT_NAME> \
--verifier blockscout --verifier-url <VERIFIER_URL>
```

### Upgrade Contract

Upgrading an existing contract is done as per the instructions in [openzeppelin-foundry-upgrades](https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades) repository.

First, we create a new contract with its name as `ContractNameV2`, and then we execute the following command:

```sh
forge script ./script/Deploy.s.sol:Upgrade<CONTRACT_NAME> \
--rpc-url <RPC_URL> \
--account <WALLET_NAME> --broadcast \
--sender <WALLET_ADDRESS> \
--verify --verifier blockscout \
--verifier-url <VERIFIER_URL>
```

> [!NOTE]
>
> The `--sender <ADDRESS>` field is mandatory when deploying a contract, it can be obtained with the command below, which will prompt for keystore password:
>
> ```sh
> cast wallet address --account <WALLET_NAME>
> ```

## Testing & Diagnostics

Run tests on local network:

```sh
FOUNDRY_PROFILE=test forge test

# or -vvv to show reverts in detail
FOUNDRY_PROFILE=test forge test -vvv
```

or fork an existing chain and run the tests on it:

```sh
FOUNDRY_PROFILE=test forge test --rpc-url <RPC_URL>
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

### Gas Snapshot

You can examine the gas usage metrics using the command:

```sh
FOUNDRY_PROFILE=test forge snapshot --snap ./test/.gas-snapshot
```

You can see the snapshot `.gas-snapshot` file in the current directory.

### Styling

You can format the contracts with:

```sh
forge fmt ./src/**/*.sol ./script/**/*.sol
```

If you have solhint installed, you can lint all contracts with:

```sh
solhint 'src/**/*.sol' 'script/**/*.sol'
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
