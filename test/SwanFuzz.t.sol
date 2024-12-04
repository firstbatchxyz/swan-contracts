// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Vm} from "forge-std/Vm.sol";
import {Helper} from "./Helper.t.sol";

import {BuyerAgent, BuyerAgentFactory} from "../src/BuyerAgent.sol";
import {SwanAssetFactory, SwanAsset} from "../src/SwanAsset.sol";
import {Swan, SwanMarketParameters} from "../src/Swan.sol";
import {WETH9} from "./WETH9.sol";
import {LLMOracleRegistry} from "@firstbatch/dria-oracle-contracts/LLMOracleRegistry.sol";
import {
    LLMOracleCoordinator, LLMOracleTaskParameters
} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {console} from "forge-std/Test.sol";

/// @notice Fuzz test is used to test call the functions with random values multiple times
contract SwanFuzz is Helper {
    modifier fund() {
        // fund dria
        deal(address(token), dria, 1 ether);

        // fund sellers
        for (uint256 i; i < sellers.length; i++) {
            deal(address(token), sellers[i], 5 ether);
            assertEq(token.balanceOf(sellers[i]), 5 ether);
            vm.label(address(sellers[i]), string.concat("Seller#", vm.toString(i + 1)));
        }
        _;
    }

    /// @notice Calculate royalties
    function testFuzz_CalculateRoyalties(uint256 price, uint256 agentFee, uint256 driaFee) external createBuyers {
        agentFee = bound(agentFee, 1, 80);
        require(agentFee <= 80 && agentFee > 0, "Agent fee is not correctly set");

        driaFee = bound(driaFee, 1, 80);
        require(driaFee <= 80 && driaFee > 0, "Dria fee is not correctly set");

        price = bound(price, 0.000001 ether, 0.2 ether);
        require(price >= 0.000001 ether && price <= 0.2 ether, "Price is not correctly set");

        uint256 expectedTotalFee = Math.mulDiv(price, (agentFee * 100), 10000);
        uint256 expectedDriaFee =
            Math.mulDiv(expectedTotalFee, (swan.getCurrentMarketParameters().platformFee * 100), 10000);
        uint256 expectedAgentFee = expectedTotalFee - expectedDriaFee;

        assertEq(expectedAgentFee + expectedDriaFee, expectedTotalFee, "Invalid fee calculation");
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
        sellIntervalForFirstSet = bound(sellIntervalForFirstSet, 15 minutes, 2 days);
        require(
            sellIntervalForFirstSet >= 15 minutes && sellIntervalForFirstSet <= 2 days,
            "SellInterval is not correctly set"
        );

        sellIntervalForSecondSet = bound(sellIntervalForSecondSet, 15 minutes, 2 days);
        require(
            sellIntervalForSecondSet >= 15 minutes && sellIntervalForSecondSet <= 2 days,
            "SellInterval is not correctly set"
        );

        buyIntervalForFirstset = bound(buyIntervalForFirstset, 15 minutes, 2 days);
        require(
            buyIntervalForFirstset >= 15 minutes && buyIntervalForFirstset <= 2 days, "BuyInterval is not correctly set"
        );

        buyIntervalForSecondSet = bound(buyIntervalForSecondSet, 15 minutes, 2 days);
        require(
            buyIntervalForSecondSet >= 15 minutes && buyIntervalForSecondSet <= 2 days,
            "BuyInterval is not correctly set"
        );

        withdrawIntervalForFirstSet = bound(withdrawIntervalForFirstSet, 15 minutes, 2 days);
        require(
            withdrawIntervalForFirstSet >= 15 minutes && withdrawIntervalForFirstSet <= 2 days,
            "WithdrawInterval is not correctly set"
        );

        withdrawIntervalForSecondSet = bound(withdrawIntervalForSecondSet, 15 minutes, 2 days);
        require(
            withdrawIntervalForSecondSet >= 15 minutes && withdrawIntervalForSecondSet <= 2 days,
            "WithdrawInterval is not correctly set"
        );

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

    function testFuzz_TransferOwnership(address newOwner) public {
        vm.assume(newOwner != address(0x0));

        vm.prank(dria);
        swan.transferOwnership(newOwner);
    }

    function testFuzz_ListAsset(
        string calldata name,
        string calldata symbol,
        bytes calldata desc,
        uint256 price,
        string memory agentName,
        string memory agentDesc,
        uint96 agentFee,
        uint256 amountPerRound
    ) public fund sellersApproveToSwan {
        // Assume the price is within a reasonable range and buyer is not zero address
        amountPerRound = bound(amountPerRound, 0.1 ether, 1 ether);
        require(amountPerRound >= 0.1 ether && amountPerRound <= 1 ether, "Amount per round is not correctly set");

        agentFee = uint96(bound(agentFee, 1, marketParameters.maxBuyerAgentFee - 1));
        require(agentFee < marketParameters.maxBuyerAgentFee && agentFee > 0, "Agent fee is not correctly set");

        price = bound(price, marketParameters.minAssetPrice, amountPerRound - 1);
        require(price >= marketParameters.minAssetPrice && price <= amountPerRound - 1, "Price is not correctly set");

        // Create a buyer agent
        vm.prank(buyerAgentOwners[0]);
        BuyerAgent _agent = swan.createBuyer(agentName, agentDesc, agentFee, amountPerRound);

        // List the asset
        vm.prank(sellers[0]);
        swan.list(name, symbol, desc, price, address(_agent));

        // Check that the asset is listed correctly
        address asset = swan.getListedAssets(address(_agent), 0)[0];
        Swan.AssetListing memory listing = swan.getListing(asset);
        assertEq(listing.price, price);
        assertEq(listing.buyer, address(_agent));
    }
}
