// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
import {Helper} from "./Helper.t.sol";
import {WETH9} from "./WETH9.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {BuyerAgent, BuyerAgentFactory} from "../src/BuyerAgent.sol";
import {LLMOracleCoordinator} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";
import {SwanAssetFactory} from "../src/SwanAsset.sol";
import {LLMOracleTaskParameters} from "@firstbatch/dria-oracle-contracts/LLMOracleTask.sol";
import {LLMOracleRegistry} from "@firstbatch/dria-oracle-contracts/LLMOracleRegistry.sol";
import {Swan} from "../src/Swan.sol";
import {console} from "forge-std/Test.sol";

contract BuyerAgentTest is Helper {
    address agentOwner;
    BuyerAgent agent;

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

        require(address(buyerAgentFactory) != address(0), "BuyerAgentFactory not deployed");
        require(address(swanAssetFactory) != address(0), "SwanAssetFactory not deployed");

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

        vm.label(address(swan), "Swan");
        vm.label(address(token), "WETH");
        vm.label(address(this), "BuyerAgentTest");
        vm.label(address(oracleRegistry), "LLMOracleRegistry");
        vm.label(address(oracleCoordinator), "LLMOracleCoordinator");
        vm.label(address(buyerAgentFactory), "BuyerAgentFactory");
        vm.label(address(swanAssetFactory), "SwanAssetFactory");
        _;
    }

    modifier createBuyers() override {
        for (uint256 i = 0; i < buyerAgentOwners.length; i++) {
            // fund buyer agent owner
            deal(address(token), buyerAgentOwners[i], 3 ether);

            vm.startPrank(buyerAgentOwners[i]);
            BuyerAgent buyerAgent = swan.createBuyer(
                buyerAgentParameters[i].name,
                buyerAgentParameters[i].description,
                buyerAgentParameters[i].royaltyFee,
                buyerAgentParameters[i].amountPerRound
            );

            buyerAgents.push(buyerAgent);
            vm.label(address(buyerAgent), string.concat("BuyerAgent#", vm.toString(i + 1)));

            // transfer tokens to agent
            token.transfer(address(buyerAgent), amountPerRound);
            assertEq(token.balanceOf(address(buyerAgent)), amountPerRound);
            vm.stopPrank();
        }

        agentOwner = buyerAgentOwners[0];
        agent = buyerAgents[0];

        currPhase = BuyerAgent.Phase.Sell;
        currRound = 0;
        _;
    }

    /// @notice Buyer agent should be in sell phase
    function test_InSellPhase() external deployment createBuyers {
        // get curr phase
        (, BuyerAgent.Phase _phase,) = agent.getRoundPhase();
        assertEq(uint8(_phase), uint8(currPhase));
    }

    /// @dev Agent owner cannot set feeRoyalty in sell phase
    function test_RevertWhen_SetRoyaltyInSellPhase() external deployment createBuyers {
        vm.prank(agentOwner);
        vm.expectRevert(
            abi.encodeWithSelector(BuyerAgent.InvalidPhase.selector, BuyerAgent.Phase.Sell, BuyerAgent.Phase.Withdraw)
        );
        agent.setFeeRoyalty(10);
    }

    /// @notice Test that the buyer agent is in buy phase
    function test_InBuyPhase() external deployment createBuyers {
        vm.warp(agent.createdAt() + marketParameters.sellInterval);
        currPhase = BuyerAgent.Phase.Buy;

        (, BuyerAgent.Phase _phase,) = agent.getRoundPhase();
        assertEq(uint8(_phase), uint8(currPhase));
    }

    /// @dev Agent owner cannot set amountPerRound in buy phase
    function test_RevertWhen_SetAmountPerRoundInBuyPhase() external deployment createBuyers {
        vm.warp(agent.createdAt() + marketParameters.sellInterval);

        vm.prank(agentOwner);
        vm.expectRevert(
            abi.encodeWithSelector(BuyerAgent.InvalidPhase.selector, BuyerAgent.Phase.Buy, BuyerAgent.Phase.Withdraw)
        );
        agent.setAmountPerRound(2 ether);
    }

    /// @notice Test that the buyer agent owner cannot withdraw in buy phase
    function test_RevertWhen_WithdrawInBuyPhase() external deployment createBuyers {
        // owner cannot withdraw more than minFundAmount from his agent
        vm.warp(agent.createdAt() + marketParameters.sellInterval);

        // get the contract balance
        uint256 treasuary = agent.treasury();

        vm.prank(agentOwner);
        // try to withdraw all balance
        vm.expectRevert(abi.encodeWithSelector(BuyerAgent.MinFundSubceeded.selector, treasuary));
        agent.withdraw(uint96(treasuary));
    }

    /// @notice Test that the non-owner cannot withdraw
    function test_RevertWhen_WithdrawByAnotherOwner() external deployment createBuyers {
        // royalty fee can be set only in withdraw phase by only agent owner
        vm.warp(agent.createdAt() + marketParameters.sellInterval + marketParameters.buyInterval);
        currPhase = BuyerAgent.Phase.Withdraw;

        (, BuyerAgent.Phase _phase,) = agent.getRoundPhase();
        assertEq(uint8(_phase), uint8(currPhase));

        // not allowed to withdraw by non owner
        vm.prank(buyerAgentOwners[1]);
        vm.expectRevert(abi.encodeWithSelector(BuyerAgent.Unauthorized.selector, buyerAgentOwners[1]));
        agent.withdraw(1 ether);
    }

    /// @notice Test that the buyer agent owner must set feeRoyalty between 1-100
    function test_RevertWhen_SetFeeWithInvalidRoyalty() external deployment createBuyers {
        vm.warp(agent.createdAt() + marketParameters.sellInterval + marketParameters.buyInterval);

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
    function test_SetRoyaltyAndAmountPerRound() external deployment createBuyers {
        vm.warp(agent.createdAt() + marketParameters.sellInterval + marketParameters.buyInterval);

        uint96 newRoyaltyFee = 20;
        uint256 newAmountPerRound = 0.25 ether;

        vm.startPrank(agentOwner);
        agent.setFeeRoyalty(newRoyaltyFee);
        agent.setAmountPerRound(newAmountPerRound);

        assertEq(agent.royaltyFee(), newRoyaltyFee);
        assertEq(agent.amountPerRound(), newAmountPerRound);

        vm.stopPrank();
    }

    /// @notice Test that the buyer agent owner can withdraw in withdraw phase
    function test_WithdrawInWithdrawPhase() external deployment createBuyers {
        vm.warp(agent.createdAt() + marketParameters.sellInterval + marketParameters.buyInterval);

        vm.startPrank(agentOwner);
        agent.withdraw(uint96(token.balanceOf(address(agent))));
    }
}
