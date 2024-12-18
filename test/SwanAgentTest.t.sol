// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Vm} from "forge-std/Vm.sol";
import {Helper} from "./Helper.t.sol";

import {WETH9} from "./contracts/WETH9.sol";
import {SwanAgent} from "../src/SwanAgent.sol";
import {LLMOracleCoordinator} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";
import {LLMOracleTaskParameters} from "@firstbatch/dria-oracle-contracts/LLMOracleTask.sol";
import {LLMOracleRegistry} from "@firstbatch/dria-oracle-contracts/LLMOracleRegistry.sol";
import {Swan} from "../src/Swan.sol";

contract SwanAgentTest is Helper {
    /// @notice Agent should be in Listing Phase
    function test_InListingPhase() external createAgents {
        // get curr phase
        (, SwanAgent.Phase _phase,) = agent.getRoundPhase();
        assertEq(uint8(_phase), uint8(currPhase));
    }

    /// @dev Agent owner cannot set feeRoyalty in Listing Phase
    function test_RevertWhen_SetRoyaltyInListingPhase() external createAgents {
        vm.prank(agentOwner);
        vm.expectRevert(
            abi.encodeWithSelector(SwanAgent.InvalidPhase.selector, SwanAgent.Phase.Listing, SwanAgent.Phase.Withdraw)
        );
        agent.setFeeRoyalty(10);
    }

    /// @notice Test that the agent is in Buy Phase
    function test_InBuyPhase() external createAgents {
        uint256 _timeToBuyPhaseOfTheFirstRound = agent.createdAt() + swan.getCurrentMarketParameters().listingInterval;
        increaseTime(_timeToBuyPhaseOfTheFirstRound, agent, SwanAgent.Phase.Buy, 0);

        currPhase = SwanAgent.Phase.Buy;

        (, SwanAgent.Phase _phase,) = agent.getRoundPhase();
        assertEq(uint8(_phase), uint8(currPhase));
    }

    /// @dev Agent owner cannot set amountPerRound in Buy Phase
    function test_RevertWhen_SetAmountPerRoundInBuyPhase() external createAgents {
        increaseTime(agent.createdAt() + marketParameters.listingInterval, agent, SwanAgent.Phase.Buy, 0);

        vm.prank(agentOwner);
        vm.expectRevert(
            abi.encodeWithSelector(SwanAgent.InvalidPhase.selector, SwanAgent.Phase.Buy, SwanAgent.Phase.Withdraw)
        );
        agent.setAmountPerRound(2 ether);
    }

    /// @notice Test that the agent owner cannot withdraw in Buy Phase
    function test_RevertWhen_WithdrawInBuyPhase() external createAgents {
        // owner cannot withdraw more than minFundAmount from his agent
        increaseTime(agent.createdAt() + marketParameters.listingInterval, agent, SwanAgent.Phase.Buy, 0);

        // get the contract balance
        uint256 treasuary = agent.treasury();

        vm.prank(agentOwner);
        // try to withdraw all balance
        vm.expectRevert(abi.encodeWithSelector(SwanAgent.MinFundSubceeded.selector, treasuary));
        agent.withdraw(uint96(treasuary));
    }

    /// @notice Test that the non-owner cannot withdraw
    function test_RevertWhen_WithdrawByAnotherOwner() external createAgents {
        increaseTime(
            agent.createdAt() + marketParameters.listingInterval + marketParameters.buyInterval,
            agent,
            SwanAgent.Phase.Withdraw,
            0
        );

        currPhase = SwanAgent.Phase.Withdraw;

        // not allowed to withdraw by non owner
        vm.prank(agentOwners[1]);
        vm.expectRevert(abi.encodeWithSelector(SwanAgent.Unauthorized.selector, agentOwners[1]));
        agent.withdraw(1 ether);
    }

    /// @notice Test that the AI agent owner must set feeRoyalty between 1-100
    /// @dev feeRoyalty can be set ONLY in Withdraw Phase by only agent owner
    function test_RevertWhen_SetFeeWithInvalidRoyalty() external createAgents {
        increaseTime(
            agent.createdAt() + marketParameters.listingInterval + marketParameters.buyInterval,
            agent,
            SwanAgent.Phase.Withdraw,
            0
        );

        uint96 _biggerRoyalty = 1000;
        uint96 _smallerRoyalty = 0;

        vm.startPrank(agentOwner);
        vm.expectRevert(abi.encodeWithSelector(SwanAgent.InvalidFee.selector, _biggerRoyalty));
        agent.setFeeRoyalty(_biggerRoyalty);

        vm.expectRevert(abi.encodeWithSelector(SwanAgent.InvalidFee.selector, _smallerRoyalty));
        agent.setFeeRoyalty(_smallerRoyalty);
        vm.stopPrank();
    }

    /// @notice Test that the AI agent owner can set feeRoyalty and amountPerRound in Withdraw Phase
    function test_SetRoyaltyAndAmountPerRound() external createAgents {
        increaseTime(
            agent.createdAt() + marketParameters.listingInterval + marketParameters.buyInterval,
            agent,
            SwanAgent.Phase.Withdraw,
            0
        );

        uint96 _newFeeRoyalty = 20;
        uint256 _newAmountPerRound = 0.25 ether;

        vm.startPrank(agentOwner);
        agent.setFeeRoyalty(_newFeeRoyalty);
        agent.setAmountPerRound(_newAmountPerRound);
        vm.stopPrank();

        assertEq(agent.feeRoyalty(), _newFeeRoyalty);
        assertEq(agent.amountPerRound(), _newAmountPerRound);
    }

    /// @notice Test that the agent owner can withdraw in Withdraw Phase
    function test_WithdrawInWithdrawPhase() external createAgents {
        increaseTime(
            agent.createdAt() + marketParameters.listingInterval + marketParameters.buyInterval,
            agent,
            SwanAgent.Phase.Withdraw,
            0
        );

        vm.startPrank(agentOwner);
        agent.withdraw(uint96(token.balanceOf(address(agent))));
    }
}
