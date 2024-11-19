// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Script} from "../lib/forge-std/src/Script.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import {LLMOracleRegistry} from "../contracts/llm/LLMOracleRegistry.sol";
import {LLMOracleCoordinator, LLMOracleTaskParameters} from "../contracts/llm/LLMOracleCoordinator.sol";
import {BuyerAgentFactory} from "../contracts/swan/BuyerAgent.sol";
import {SwanAssetFactory} from "../contracts/swan/SwanAsset.sol";
import {Swan, SwanMarketParameters} from "../contracts/swan/Swan.sol";

contract Deploy is Script {
    LLMOracleCoordinator public oracleCoordinator;
    LLMOracleRegistry public oracleRegistry;

    BuyerAgentFactory public buyerAgentFactory;
    SwanAssetFactory public swanAssetFactory;
    Swan public swan;

    HelperConfig public config;

    function run() external {
        config = new HelperConfig();

        vm.startBroadcast();
        deployLLM();
        deployFactories();
        deploySwan();
        vm.stopBroadcast();
    }

    function deployLLM() internal {
        // get stakes
        (uint256 genStake, uint256 valStake) = config.stakes();

        // get fees
        (uint256 platformFee, uint256 genFee, uint256 valFee) = config.fees();

        // deploy llm contracts
        address registryProxy = Upgrades.deployUUPSProxy(
            "LLMOracleRegistry.sol",
            abi.encodeCall(LLMOracleRegistry.initialize, (genStake, valStake, address(config.token())))
        );

        // wrap proxy with the LLMOracleRegistry
        oracleRegistry = LLMOracleRegistry(registryProxy);

        // deploy coordinator contract
        address coordinatorProxy = Upgrades.deployUUPSProxy(
            "LLMOracleCoordinator.sol",
            abi.encodeCall(
                LLMOracleCoordinator.initialize,
                (address(oracleRegistry), address(config.token()), platformFee, genFee, valFee)
            )
        );

        oracleCoordinator = LLMOracleCoordinator(coordinatorProxy);
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
                        block.timestamp
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
    }
}
