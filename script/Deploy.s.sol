// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {LLMOracleRegistry} from "@firstbatch/dria-oracle-contracts/LLMOracleRegistry.sol";
import {
    LLMOracleCoordinator, LLMOracleTaskParameters
} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";
import {BuyerAgentFactory} from "../src/BuyerAgent.sol";
import {SwanAssetFactory} from "../src/SwanAsset.sol";
import {Swan, SwanMarketParameters} from "../src/Swan.sol";
import {Vm} from "forge-std/Vm.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract Deploy is Script {
    // contracts
    LLMOracleCoordinator public oracleCoordinator;
    LLMOracleRegistry public oracleRegistry;
    BuyerAgentFactory public buyerAgentFactory;
    SwanAssetFactory public swanAssetFactory;
    Swan public swan;

    // implementation addresses
    address registryImplementation;
    address coordinatorImplementation;
    address swanImplementation;

    HelperConfig public config;
    uint256 chainId;

    function run() external {
        chainId = block.chainid;
        config = new HelperConfig();

        vm.startBroadcast();
        deployLLM();
        deployFactories();
        deploySwan();
        vm.stopBroadcast();

        writeContractAddresses();
    }

    function deployLLM() internal {
        // get stakes
        (uint256 genStake, uint256 valStake) = config.stakes();

        // get fees
        (uint256 platformFee, uint256 genFee, uint256 valFee) = config.fees();

        // deploy llm contracts
        address registryProxy = Upgrades.deployUUPSProxy(
            "LLMOracleRegistry.sol",
            abi.encodeCall(
                LLMOracleRegistry.initialize,
                (genStake, valStake, address(config.token()), config.minRegistrationTime())
            )
        );

        // wrap proxy with the LLMOracleRegistry
        oracleRegistry = LLMOracleRegistry(registryProxy);
        registryImplementation = Upgrades.getImplementationAddress(registryProxy);

        // deploy coordinator contract
        address coordinatorProxy = Upgrades.deployUUPSProxy(
            "LLMOracleCoordinator.sol",
            abi.encodeCall(
                LLMOracleCoordinator.initialize,
                (
                    address(oracleRegistry),
                    address(config.token()),
                    platformFee,
                    genFee,
                    valFee,
                    config.minScore(),
                    config.maxScore()
                )
            )
        );

        oracleCoordinator = LLMOracleCoordinator(coordinatorProxy);
        coordinatorImplementation = Upgrades.getImplementationAddress(coordinatorProxy);
    }

    function deployFactories() internal {
        buyerAgentFactory = new BuyerAgentFactory();
        swanAssetFactory = new SwanAssetFactory();
    }

    function deploySwan() internal {
        // get market params
        (
            uint256 withdrawInterval,
            uint256 sellInterval,
            uint256 buyInterval,
            uint256 platformFee,
            uint256 maxAssetCount,
            uint256 minAssetPrice,
            /* timestamp */
            ,
            uint8 maxBuyerAgentFee
        ) = config.marketParams();

        // get llm params
        (uint8 diff, uint40 numGen, uint40 numVal) = config.taskParams();

        // deploy swan
        address swanProxy = Upgrades.deployUUPSProxy(
            "Swan.sol",
            abi.encodeCall(
                Swan.initialize,
                (
                    SwanMarketParameters(
                        withdrawInterval,
                        sellInterval,
                        buyInterval,
                        platformFee,
                        maxAssetCount,
                        minAssetPrice,
                        block.timestamp,
                        maxBuyerAgentFee
                    ),
                    LLMOracleTaskParameters(diff, numGen, numVal),
                    address(oracleCoordinator),
                    address(config.token()),
                    address(buyerAgentFactory),
                    address(swanAssetFactory)
                )
            )
        );
        swan = Swan(swanProxy);
        swanImplementation = Upgrades.getImplementationAddress(swanProxy);
    }

    function writeContractAddresses() internal {
        // create a deployment file if not exist
        string memory dir = "deployment/";
        string memory fileName = Strings.toString(chainId);
        string memory path = string.concat(dir, fileName, ".json");

        // create dir if it doesn't exist
        vm.createDir(dir, true);

        string memory contracts = string.concat(
            "{",
            '  "LLMOracleRegistry": {',
            '    "proxyAddr": "',
            Strings.toHexString(uint256(uint160(address(oracleRegistry))), 20),
            '",',
            '    "implAddr": "',
            Strings.toHexString(uint256(uint160(address(registryImplementation))), 20),
            '"',
            "  },",
            '  "LLMOracleCoordinator": {',
            '    "proxyAddr": "',
            Strings.toHexString(uint256(uint160(address(oracleCoordinator))), 20),
            '",',
            '    "implAddr": "',
            Strings.toHexString(uint256(uint160(address(coordinatorImplementation))), 20),
            '"',
            "  },",
            '  "Swan": {',
            '    "proxyAddr": "',
            Strings.toHexString(uint256(uint160(address(swan))), 20),
            '",',
            '    "implAddr": "',
            Strings.toHexString(uint256(uint160(address(swanImplementation))), 20),
            '"',
            "  },",
            '  "BuyerAgentFactory": "',
            Strings.toHexString(uint256(uint160(address(buyerAgentFactory))), 20),
            '",',
            '  "SwanAssetFactory": "',
            Strings.toHexString(uint256(uint160(address(swanAssetFactory))), 20),
            '"' "}"
        );

        vm.writeJson(contracts, path);
    }
}
