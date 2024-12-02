// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Vm} from "forge-std/Vm.sol";
import {Helper} from "./Helper.t.sol";

import {WETH9} from "./WETH9.sol";
import {BuyerAgent, BuyerAgentFactory} from "../src/BuyerAgent.sol";
import {LLMOracleCoordinator} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";
import {SwanAssetFactory} from "../src/SwanAsset.sol";
import {LLMOracleTaskParameters} from "@firstbatch/dria-oracle-contracts/LLMOracleTask.sol";
import {LLMOracleRegistry} from "@firstbatch/dria-oracle-contracts/LLMOracleRegistry.sol";
import {Swan} from "../src/Swan.sol";

contract BuyerAgentTest is Helper {
    /// @notice Buyer agent should be in sell phase
    function test_InSellPhase() external createBuyers {
        // get curr phase
        (, BuyerAgent.Phase _phase,) = agent.getRoundPhase();
        assertEq(uint8(_phase), uint8(currPhase));
    }

    /// @dev Agent owner cannot set feeRoyalty in sell phase
    function test_RevertWhen_SetRoyaltyInSellPhase() external createBuyers {
        vm.prank(agentOwner);
        vm.expectRevert(
            abi.encodeWithSelector(BuyerAgent.InvalidPhase.selector, BuyerAgent.Phase.Sell, BuyerAgent.Phase.Withdraw)
        );
        agent.setFeeRoyalty(10);
    }

    /// @notice Test that the buyer agent is in buy phase
    function test_InBuyPhase() external createBuyers {
        uint256 timeToBuyPhaseOfTheFirstRound = agent.createdAt() + swan.getCurrentMarketParameters().sellInterval;
        increaseTime(timeToBuyPhaseOfTheFirstRound, agent, BuyerAgent.Phase.Buy, 0);

        currPhase = BuyerAgent.Phase.Buy;

        (, BuyerAgent.Phase _phase,) = agent.getRoundPhase();
        assertEq(uint8(_phase), uint8(currPhase));
    }

    /// @dev Agent owner cannot set amountPerRound in buy phase
    function test_RevertWhen_SetAmountPerRoundInBuyPhase() external createBuyers {
        increaseTime(agent.createdAt() + marketParameters.sellInterval, agent, BuyerAgent.Phase.Buy, 0);

        vm.prank(agentOwner);
        vm.expectRevert(
            abi.encodeWithSelector(BuyerAgent.InvalidPhase.selector, BuyerAgent.Phase.Buy, BuyerAgent.Phase.Withdraw)
        );
        agent.setAmountPerRound(2 ether);
    }

    /// @notice Test that the buyer agent owner cannot withdraw in buy phase
    function test_RevertWhen_WithdrawInBuyPhase() external createBuyers {
        // owner cannot withdraw more than minFundAmount from his agent
        increaseTime(agent.createdAt() + marketParameters.sellInterval, agent, BuyerAgent.Phase.Buy, 0);

        // get the contract balance
        uint256 treasuary = agent.treasury();

        vm.prank(agentOwner);
        // try to withdraw all balance
        vm.expectRevert(abi.encodeWithSelector(BuyerAgent.MinFundSubceeded.selector, treasuary));
        agent.withdraw(uint96(treasuary));
    }

    /// @notice Test that the non-owner cannot withdraw
    function test_RevertWhen_WithdrawByAnotherOwner() external createBuyers {
        // feeRoyalty can be set only in withdraw phase by only agent owner
        increaseTime(
            agent.createdAt() + marketParameters.sellInterval + marketParameters.buyInterval,
            agent,
            BuyerAgent.Phase.Withdraw,
            0
        );
        currPhase = BuyerAgent.Phase.Withdraw;

        // not allowed to withdraw by non owner
        vm.prank(buyerAgentOwners[1]);
        vm.expectRevert(abi.encodeWithSelector(BuyerAgent.Unauthorized.selector, buyerAgentOwners[1]));
        agent.withdraw(1 ether);
    }

    /// @notice Test that the buyer agent owner must set feeRoyalty between 1-100
    function test_RevertWhen_SetFeeWithInvalidRoyalty() external createBuyers {
        increaseTime(
            agent.createdAt() + marketParameters.sellInterval + marketParameters.buyInterval,
            agent,
            BuyerAgent.Phase.Withdraw,
            0
        );

        uint96 biggerRoyalty = 1000;
        uint96 smallerRoyalty = 0;

        vm.startPrank(agentOwner);
        vm.expectRevert(abi.encodeWithSelector(BuyerAgent.InvalidFee.selector, biggerRoyalty));
        agent.setFeeRoyalty(biggerRoyalty);

        vm.expectRevert(abi.encodeWithSelector(BuyerAgent.InvalidFee.selector, smallerRoyalty));
        agent.setFeeRoyalty(smallerRoyalty);
        vm.stopPrank();
    }

    /// @notice Test that the buyer agent owner can set feeRoyalty and amountPerRound in withdraw phase
    function test_SetRoyaltyAndAmountPerRound() external createBuyers {
        increaseTime(
            agent.createdAt() + marketParameters.sellInterval + marketParameters.buyInterval,
            agent,
            BuyerAgent.Phase.Withdraw,
            0
        );

        uint96 newFeeRoyalty = 20;
        uint256 newAmountPerRound = 0.25 ether;

        vm.startPrank(agentOwner);
        agent.setFeeRoyalty(newFeeRoyalty);
        agent.setAmountPerRound(newAmountPerRound);

        assertEq(agent.feeRoyalty(), newFeeRoyalty);
        assertEq(agent.amountPerRound(), newAmountPerRound);

        vm.stopPrank();
    }

    /// @notice Test that the buyer agent owner can withdraw in withdraw phase
    function test_WithdrawInWithdrawPhase() external createBuyers {
        increaseTime(
            agent.createdAt() + marketParameters.sellInterval + marketParameters.buyInterval,
            agent,
            BuyerAgent.Phase.Withdraw,
            0
        );

        vm.startPrank(agentOwner);
        agent.withdraw(uint96(token.balanceOf(address(agent))));
    }
}
