// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Helper} from "./Helper.t.sol";
import {console} from "forge-std/Test.sol";

import {BuyerAgent, BuyerAgentFactory} from "../src/BuyerAgent.sol";
import {SwanAssetFactory, SwanAsset} from "../src/SwanAsset.sol";
import {Swan, SwanMarketParameters} from "../src/Swan.sol";
import {WETH9} from "./WETH9.sol";
import {LLMOracleRegistry} from "@firstbatch/dria-oracle-contracts/LLMOracleRegistry.sol";
import {
    LLMOracleCoordinator, LLMOracleTaskParameters
} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";

contract SwanIntervalsTest is Helper {
    /// @notice Check the current phase is Sell right after creation of buyer agent
    function test_InSellPhase() external createBuyers {
        // agent should be in sell phase right after creation
        checkRoundAndPhase(buyerAgents[0], BuyerAgent.Phase.Sell, 0);
    }

    /// @notice Check the current phase is Buy after increase time to buy phase
    function test_InBuyPhase() external createBuyers {
        BuyerAgent agent = buyerAgents[0];
        increaseTime(agent.createdAt() + swan.getCurrentMarketParameters().sellInterval, agent, BuyerAgent.Phase.Buy, 0);
        checkRoundAndPhase(agent, BuyerAgent.Phase.Buy, 0);
    }

    /// @notice Check the current phase is Withdraw after increase time to withdraw phase
    function test_InWithdrawPhase() external createBuyers {
        increaseTime(
            buyerAgents[0].createdAt() + swan.getCurrentMarketParameters().sellInterval
                + swan.getCurrentMarketParameters().buyInterval,
            buyerAgents[0],
            BuyerAgent.Phase.Withdraw,
            0
        );
        checkRoundAndPhase(buyerAgents[0], BuyerAgent.Phase.Withdraw, 0);
    }
}
