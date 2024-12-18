// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Helper} from "./Helper.t.sol";
import {console} from "forge-std/Test.sol";

import {SwanAgent} from "../src/SwanAgent.sol";
import {SwanArtifactFactory} from "../src/SwanArtifact.sol";
import {Swan, SwanMarketParameters} from "../src/Swan.sol";
import {WETH9} from "./contracts/WETH9.sol";
import {LLMOracleRegistry} from "@firstbatch/dria-oracle-contracts/LLMOracleRegistry.sol";
import {
    LLMOracleCoordinator, LLMOracleTaskParameters
} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";

contract SwanIntervalsTest is Helper {
    /// @notice Check the current phase is listing right after creation of buyer agent
    function test_InListingPhase() external createAgents {
        // agent should be in listing phase right after creation
        checkRoundAndPhase(agents[0], SwanAgent.Phase.Listing, 0);
    }

    /// @notice Check the current phase is Buy after increase time to buy phase
    function test_InBuyPhase() external createAgents {
        SwanAgent _agent = agents[0];
        increaseTime(
            _agent.createdAt() + swan.getCurrentMarketParameters().listingInterval, _agent, SwanAgent.Phase.Buy, 0
        );
        checkRoundAndPhase(_agent, SwanAgent.Phase.Buy, 0);
    }

    /// @notice Check the current phase is Withdraw after increase time to withdraw phase
    function test_InWithdrawPhase() external createAgents {
        SwanAgent _agent = agents[0];
        increaseTime(
            _agent.createdAt() + swan.getCurrentMarketParameters().listingInterval
                + swan.getCurrentMarketParameters().buyInterval,
            _agent,
            SwanAgent.Phase.Withdraw,
            0
        );
        checkRoundAndPhase(_agent, SwanAgent.Phase.Withdraw, 0);
    }
}
