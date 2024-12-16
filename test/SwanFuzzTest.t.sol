// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Vm} from "forge-std/Vm.sol";
import {Helper} from "./Helper.t.sol";

import {AIAgent, AIAgentFactory} from "../src/AIAgent.sol";
import {ArtifactFactory, Artifact} from "../src/Artifact.sol";
import {Swan, SwanMarketParameters} from "../src/Swan.sol";
import {WETH9} from "./WETH9.sol";
import {LLMOracleRegistry} from "@firstbatch/dria-oracle-contracts/LLMOracleRegistry.sol";
import {
    LLMOracleCoordinator, LLMOracleTaskParameters
} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {console} from "forge-std/Test.sol";

/// @notice Fuzz test is used to test call the functions with random values multiple times
contract SwanFuzzTest is Helper {
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
    function testFuzz_CalculateRoyalties(uint256 _price, uint256 _agentFee, uint256 _driaFee) external createAgents {
        _agentFee = bound(_agentFee, 1, 80);
        require(_agentFee <= 80 && _agentFee > 0, "Agent fee is not correctly set");

        _driaFee = bound(_driaFee, 1, 80);
        require(_driaFee <= 80 && _driaFee > 0, "Dria fee is not correctly set");

        _price = bound(_price, 0.000001 ether, 0.2 ether);
        require(_price >= 0.000001 ether && _price <= 0.2 ether, "Price is not correctly set");

        uint256 expectedTotalFee = Math.mulDiv(_price, (_agentFee * 100), 10000);
        uint256 expectedDriaFee =
            Math.mulDiv(expectedTotalFee, (swan.getCurrentMarketParameters().platformFee * 100), 10000);
        uint256 expectedAgentFee = expectedTotalFee - expectedDriaFee;

        assertEq(expectedAgentFee + expectedDriaFee, expectedTotalFee, "Invalid fee calculation");
    }

    /// @notice Change the intervals and check the current phase and round is are correct
    function testFuzz_ChangeCycleTime(
        uint256 _listingIntervalForFirstSet,
        uint256 _buyIntervalForFirstset,
        uint256 _withdrawIntervalForFirstSet,
        uint256 _listingIntervalForSecondSet,
        uint256 _buyIntervalForSecondSet,
        uint256 _withdrawIntervalForSecondSet
    ) external createAgents {
        _listingIntervalForFirstSet = bound(_listingIntervalForFirstSet, 15 minutes, 2 days);
        require(
            _listingIntervalForFirstSet >= 15 minutes && _listingIntervalForFirstSet <= 2 days,
            "ListingInterval is not correctly set"
        );

        _listingIntervalForSecondSet = bound(_listingIntervalForSecondSet, 15 minutes, 2 days);
        require(
            _listingIntervalForSecondSet >= 15 minutes && _listingIntervalForSecondSet <= 2 days,
            "ListingInterval is not correctly set"
        );

        _buyIntervalForFirstset = bound(_buyIntervalForFirstset, 15 minutes, 2 days);
        require(
            _buyIntervalForFirstset >= 15 minutes && _buyIntervalForFirstset <= 2 days,
            "BuyInterval is not correctly set"
        );

        _buyIntervalForSecondSet = bound(_buyIntervalForSecondSet, 15 minutes, 2 days);
        require(
            _buyIntervalForSecondSet >= 15 minutes && _buyIntervalForSecondSet <= 2 days,
            "BuyInterval is not correctly set"
        );

        _withdrawIntervalForFirstSet = bound(_withdrawIntervalForFirstSet, 15 minutes, 2 days);
        require(
            _withdrawIntervalForFirstSet >= 15 minutes && _withdrawIntervalForFirstSet <= 2 days,
            "WithdrawInterval is not correctly set"
        );

        _withdrawIntervalForSecondSet = bound(_withdrawIntervalForSecondSet, 15 minutes, 2 days);
        require(
            _withdrawIntervalForSecondSet >= 15 minutes && _withdrawIntervalForSecondSet <= 2 days,
            "WithdrawInterval is not correctly set"
        );

        // increase time to buy phase of the second round
        increaseTime(
            agents[0].createdAt() + swan.getCurrentMarketParameters().listingInterval, agents[0], AIAgent.Phase.Buy, 0
        );

        // change cycle time
        setMarketParameters(
            SwanMarketParameters({
                withdrawInterval: _withdrawIntervalForFirstSet,
                listingInterval: _listingIntervalForFirstSet,
                buyInterval: _buyIntervalForFirstset,
                platformFee: 2,
                maxArtifactCount: 3,
                timestamp: block.timestamp,
                minArtifactPrice: 0.00001 ether,
                maxAgentFee: 80
            })
        );

        // get all params
        SwanMarketParameters[] memory _allParams = swan.getMarketParameters();
        assertEq(_allParams.length, 2);
        (uint256 _currRound, AIAgent.Phase _phase,) = agents[0].getRoundPhase();

        assertEq(_currRound, 1);
        assertEq(uint8(_phase), uint8(AIAgent.Phase.Listing));

        uint256 _currTimestamp = block.timestamp;

        // increase time to buy phase of the second round but round comes +1 because of the setMarketParameters call
        // AIAgents[0] should be in buy phase of second round
        increaseTime(
            _currTimestamp + (2 * swan.getCurrentMarketParameters().listingInterval)
                + swan.getCurrentMarketParameters().buyInterval + swan.getCurrentMarketParameters().withdrawInterval,
            agents[0],
            AIAgent.Phase.Buy,
            2
        );

        // deploy new AI agent
        vm.prank(agentOwners[0]);
        AIAgent _agentAfterFirstSet = swan.createAgent(
            agentParameters[1].name,
            agentParameters[1].description,
            agentParameters[1].feeRoyalty,
            agentParameters[1].amountPerRound
        );

        // _agentAfterFirstSet should be in listing phase of the first round
        checkRoundAndPhase(_agentAfterFirstSet, AIAgent.Phase.Listing, 0);

        // change cycle time
        setMarketParameters(
            SwanMarketParameters({
                withdrawInterval: _withdrawIntervalForSecondSet,
                listingInterval: _listingIntervalForSecondSet,
                buyInterval: _buyIntervalForSecondSet,
                platformFee: 2, // percentage
                maxArtifactCount: 3,
                timestamp: block.timestamp,
                minArtifactPrice: 0.00001 ether,
                maxAgentFee: 80
            })
        );

        // get all params
        _allParams = swan.getMarketParameters();
        assertEq(_allParams.length, 3);

        // AIAgents[0] should be in listing phase of the fourth round (2 more increase time + 2 for setting new params)
        checkRoundAndPhase(agents[0], AIAgent.Phase.Listing, 3);

        // agentAfterFirstSet should be in listing phase of the second round
        checkRoundAndPhase(_agentAfterFirstSet, AIAgent.Phase.Listing, 1);
    }

    function testFuzz_TransferOwnership(address _newOwner) public {
        vm.assume(_newOwner != address(0x0));

        vm.prank(dria);
        swan.transferOwnership(_newOwner);
    }

    function testFuzz_ListArtifact(
        string calldata _name,
        string calldata _symbol,
        bytes calldata _desc,
        uint256 _price,
        string memory _agentName,
        string memory _agentDesc,
        uint96 _agentFee,
        uint256 _amountPerRound
    ) public fund sellersApproveToSwan {
        // Assume the price is within a reasonable range and agenta address is not zero address
        _amountPerRound = bound(_amountPerRound, 0.1 ether, 1 ether);
        require(_amountPerRound >= 0.1 ether && _amountPerRound <= 1 ether, "Amount per round is not correctly set");

        _agentFee = uint96(bound(_agentFee, 1, marketParameters.maxAgentFee - 1));
        require(_agentFee < marketParameters.maxAgentFee && _agentFee > 0, "Agent fee is not correctly set");

        _price = bound(_price, marketParameters.minArtifactPrice, _amountPerRound - 1);
        require(
            _price >= marketParameters.minArtifactPrice && _price <= _amountPerRound - 1, "Price is not correctly set"
        );

        // Create a AI agent
        vm.prank(agentOwners[0]);
        AIAgent _agent = swan.createAgent(_agentName, _agentDesc, _agentFee, _amountPerRound);

        // List the artifact
        vm.prank(sellers[0]);
        swan.list(_name, _symbol, _desc, _price, address(_agent));

        // Check that the artifact is listed
        address artifact = swan.getListedArtifacts(address(_agent), 0)[0];
        Swan.ArtifactListing memory listing = swan.getListing(artifact);
        assertEq(listing.price, _price);
        assertEq(listing.agent, address(_agent));
    }
}
