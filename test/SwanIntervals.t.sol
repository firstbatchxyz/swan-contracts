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

    /// @notice Change the intervals and check the current phase and round is are correct
    function testFuzz_ChangeCycleTime(
        uint256 sellIntervalForFirstSet,
        uint256 buyIntervalForFirstset,
        uint256 withdrawIntervalForFirstSet,
        uint256 sellIntervalForSecondSet,
        uint256 buyIntervalForSecondSet,
        uint256 withdrawIntervalForSecondSet
    ) external createBuyers {
        vm.assume(sellIntervalForFirstSet > 15 minutes && sellIntervalForFirstSet < 2 days);
        vm.assume(buyIntervalForFirstset > 15 minutes && buyIntervalForFirstset < 2 days);
        vm.assume(withdrawIntervalForFirstSet > 15 minutes && withdrawIntervalForFirstSet < 2 days);
        vm.assume(sellIntervalForSecondSet > 15 minutes && sellIntervalForSecondSet < 2 days);
        vm.assume(buyIntervalForSecondSet > 15 minutes && buyIntervalForSecondSet < 2 days);
        vm.assume(withdrawIntervalForSecondSet > 15 minutes && withdrawIntervalForSecondSet < 2 days);

        // increase time to buy phase of the second round
        increaseTime(
            buyerAgents[0].createdAt() + swan.getCurrentMarketParameters().sellInterval,
            buyerAgents[0],
            BuyerAgent.Phase.Buy,
            0
        );

        // change cycle time
        setMarketParameters(
            SwanMarketParameters({
                withdrawInterval: withdrawIntervalForFirstSet,
                sellInterval: sellIntervalForFirstSet,
                buyInterval: buyIntervalForFirstset,
                platformFee: 2,
                maxAssetCount: 3,
                timestamp: block.timestamp,
                minAssetPrice: 0.00001 ether,
                maxBuyerAgentFee: 80
            })
        );

        // get all params
        SwanMarketParameters[] memory allParams = swan.getMarketParameters();
        assertEq(allParams.length, 2);
        (uint256 _currRound, BuyerAgent.Phase _phase,) = buyerAgents[0].getRoundPhase();

        assertEq(_currRound, 1);
        assertEq(uint8(_phase), uint8(BuyerAgent.Phase.Sell));

        uint256 currTimestamp = block.timestamp;

        // increase time to buy phase of the second round but round comes +1 because of the setMarketParameters call
        // buyerAgents[0] should be in buy phase of second round
        increaseTime(
            currTimestamp + (2 * swan.getCurrentMarketParameters().sellInterval)
                + swan.getCurrentMarketParameters().buyInterval + swan.getCurrentMarketParameters().withdrawInterval,
            buyerAgents[0],
            BuyerAgent.Phase.Buy,
            2
        );

        // deploy new buyer agent
        vm.prank(buyerAgentOwners[0]);
        BuyerAgent agentAfterFirstSet = swan.createBuyer(
            buyerAgentParameters[1].name,
            buyerAgentParameters[1].description,
            buyerAgentParameters[1].feeRoyalty,
            buyerAgentParameters[1].amountPerRound
        );

        // agentAfterFirstSet should be in sell phase of the first round
        checkRoundAndPhase(agentAfterFirstSet, BuyerAgent.Phase.Sell, 0);

        // change cycle time
        setMarketParameters(
            SwanMarketParameters({
                withdrawInterval: withdrawIntervalForSecondSet,
                sellInterval: sellIntervalForSecondSet,
                buyInterval: buyIntervalForSecondSet,
                platformFee: 2, // percentage
                maxAssetCount: 3,
                timestamp: block.timestamp,
                minAssetPrice: 0.00001 ether,
                maxBuyerAgentFee: 80
            })
        );

        // get all params
        allParams = swan.getMarketParameters();
        assertEq(allParams.length, 3);

        // buyerAgents[0] should be in sell phase of the fourth round (2 more increase time + 2 for setting new params)
        checkRoundAndPhase(buyerAgents[0], BuyerAgent.Phase.Sell, 3);

        // agentAfterFirstSet should be in sell phase of the second round
        checkRoundAndPhase(agentAfterFirstSet, BuyerAgent.Phase.Sell, 1);
    }
}
