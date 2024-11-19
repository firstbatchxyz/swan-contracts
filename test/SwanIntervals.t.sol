// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {LLMOracleTaskParameters} from "../contracts/llm/LLMOracleTask.sol";
import {LLMOracleRegistry} from "../contracts/llm/LLMOracleRegistry.sol";
import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import {LLMOracleCoordinator} from "../contracts/llm/LLMOracleCoordinator.sol";
import {BuyerAgent, BuyerAgentFactory} from "../contracts/swan/BuyerAgent.sol";
import {SwanAssetFactory, SwanAsset} from "../contracts/swan/SwanAsset.sol";
import {Swan, SwanMarketParameters} from "../contracts/swan/Swan.sol";
import {WETH9} from "../contracts/token/WETH9.sol";
import {Vm} from "../lib/forge-std/src/Vm.sol";
import {Helper} from "./Helper.t.sol";

contract SwanIntervalsTest is Helper {
    modifier deployment() {
        token = new WETH9();

        // deploy llm contracts
        vm.startPrank(dria);

        address registryProxy = Upgrades.deployUUPSProxy(
            "LLMOracleRegistry.sol",
            abi.encodeCall(
                LLMOracleRegistry.initialize, (stakes.generatorStakeAmount, stakes.validatorStakeAmount, address(token))
            )
        );

        oracleRegistry = LLMOracleRegistry(registryProxy);

        address coordinatorProxy = Upgrades.deployUUPSProxy(
            "LLMOracleCoordinator.sol",
            abi.encodeCall(
                LLMOracleCoordinator.initialize,
                (address(oracleRegistry), address(token), fees.platformFee, fees.generationFee, fees.validationFee)
            )
        );
        oracleCoordinator = LLMOracleCoordinator(coordinatorProxy);

        // deploy factory contracts
        buyerAgentFactory = new BuyerAgentFactory();
        swanAssetFactory = new SwanAssetFactory();

        // deploy swan
        address swanProxy = Upgrades.deployUUPSProxy(
            "Swan.sol",
            abi.encodeCall(
                Swan.initialize,
                (
                    marketParameters,
                    oracleParameters,
                    address(oracleCoordinator),
                    address(token),
                    address(buyerAgentFactory),
                    address(swanAssetFactory)
                )
            )
        );
        swan = Swan(swanProxy);
        vm.stopPrank();

        // label contracts to be able to identify them easily in console
        vm.label(address(swan), "Swan");
        vm.label(address(token), "WETH");
        vm.label(address(this), "SwanIntervalsTest");
        vm.label(address(oracleRegistry), "LLMOracleRegistry");
        vm.label(address(oracleCoordinator), "LLMOracleCoordinator");
        vm.label(address(buyerAgentFactory), "BuyerAgentFactory");
        vm.label(address(swanAssetFactory), "SwanAssetFactory");
        _;
    }

    /// @notice Check the current phase is Sell right after creation of buyer agent
    function test_InSellPhase() external deployment createBuyers {
        // agent should be in sell phase right after creation
        checkRoundAndPhase(buyerAgents[0], BuyerAgent.Phase.Sell, 0);
    }

    /// @notice Check the current phase is Buy increase time to buy phase
    function test_InBuyPhase() external deployment createBuyers {
        vm.warp(buyerAgents[0].createdAt() + swan.getCurrentMarketParameters().sellInterval);
        checkRoundAndPhase(buyerAgents[0], BuyerAgent.Phase.Buy, 0);
    }

    /// @notice Check the current phase is Withdraw after increase time to withdraw phase
    function test_InWithdrawPhase() external deployment createBuyers {
        vm.warp(
            buyerAgents[0].createdAt() + swan.getCurrentMarketParameters().sellInterval
                + swan.getCurrentMarketParameters().buyInterval
        );
        checkRoundAndPhase(buyerAgents[0], BuyerAgent.Phase.Withdraw, 0);
    }

    /// @notice Change the intervals and check the current phase and round is are correct
    function test_ChangeCycleTime() external deployment createBuyers {
        // increase time to buy phase of the second round
        vm.warp(buyerAgents[0].createdAt() + swan.getCurrentMarketParameters().sellInterval);
        checkRoundAndPhase(buyerAgents[0], BuyerAgent.Phase.Buy, 0);

        // decrease cycle time
        setMarketParameters(
            SwanMarketParameters({
                withdrawInterval: 60,
                sellInterval: 600,
                buyInterval: 120,
                platformFee: 2,
                maxAssetCount: 3,
                timestamp: block.timestamp,
                minAssetPrice: 0.00001 ether
            })
        );

        // get all params
        SwanMarketParameters[] memory allParams = swan.getMarketParameters();
        assertEq(allParams.length, 2);

        // should be in sell phase of second round after set
        uint256 currTimestamp = checkRoundAndPhase(buyerAgents[0], BuyerAgent.Phase.Sell, 1);

        // increase time to buy phase of the second round
        vm.warp(currTimestamp + swan.getCurrentMarketParameters().sellInterval);
        checkRoundAndPhase(buyerAgents[0], BuyerAgent.Phase.Buy, 1);

        // deploy new buyer agent
        vm.prank(buyerAgentOwners[0]);
        BuyerAgent agentAfterFirstSet = swan.createBuyer(
            buyerAgentParameters[1].name,
            buyerAgentParameters[1].description,
            buyerAgentParameters[1].royaltyFee,
            buyerAgentParameters[1].amountPerRound
        );

        // buyerAgents[0] should be in buy phase of second round
        checkRoundAndPhase(buyerAgents[0], BuyerAgent.Phase.Buy, 1);

        // agentAfterFirstSet should be in sell phase of the first round
        checkRoundAndPhase(agentAfterFirstSet, BuyerAgent.Phase.Sell, 0);

        // increase cycle time
        setMarketParameters(
            SwanMarketParameters({
                withdrawInterval: 600,
                sellInterval: 1000,
                buyInterval: 10,
                platformFee: 2, // percentage
                maxAssetCount: 3,
                timestamp: block.timestamp,
                minAssetPrice: 0.00001 ether
            })
        );

        // get all params
        allParams = swan.getMarketParameters();
        assertEq(allParams.length, 3);

        // buyerAgents[0] should be in sell phase of the third round
        checkRoundAndPhase(buyerAgents[0], BuyerAgent.Phase.Sell, 2);

        // agentAfterFirstSet should be in sell phase of the second round
        checkRoundAndPhase(agentAfterFirstSet, BuyerAgent.Phase.Sell, 1);
    }
}
