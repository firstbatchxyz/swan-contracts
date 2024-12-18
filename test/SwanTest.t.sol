// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Vm} from "forge-std/Vm.sol";
import {Helper} from "./Helper.t.sol";

import {SwanAgent, SwanAgentFactory} from "../src/SwanAgent.sol";
import {SwanArtifactFactory, SwanArtifact} from "../src/SwanArtifact.sol";
import {Swan, SwanMarketParameters} from "../src/Swan.sol";
import {LLMOracleRegistry} from "@firstbatch/dria-oracle-contracts/LLMOracleRegistry.sol";
import {WETH9} from "./contracts/WETH9.sol";
import {
    LLMOracleCoordinator, LLMOracleTaskParameters
} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {console} from "forge-std/Test.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SwanTest is Helper {
    /// @dev Fund geerators, validators, sellers, and dria
    modifier fund() {
        scores = [10, 15];

        // fund dria
        deal(address(token), dria, 1 ether);

        // fund generators
        for (uint256 i; i < generators.length; i++) {
            deal(address(token), generators[i], stakes.generatorStakeAmount);
            assertEq(token.balanceOf(generators[i]), stakes.generatorStakeAmount);
        }
        // fund validators
        for (uint256 i; i < validators.length; i++) {
            deal(address(token), validators[i], stakes.validatorStakeAmount);
            assertEq(token.balanceOf(validators[i]), stakes.validatorStakeAmount);
        }
        // fund sellers
        for (uint256 i; i < sellers.length; i++) {
            deal(address(token), sellers[i], 5 ether);
            assertEq(token.balanceOf(sellers[i]), 5 ether);
            vm.label(address(sellers[i]), string.concat("Seller#", vm.toString(i + 1)));
        }
        _;
    }

    function test_TransferOwnership() external {
        address _newOwner = address(0);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableInvalidOwner.selector, _newOwner));
        vm.startPrank(dria);
        swan.transferOwnership(_newOwner);

        _newOwner = address(0x123);
        swan.transferOwnership(_newOwner);
        assertEq(swan.owner(), _newOwner);
    }

    function test_CreateSwanAgents() external createAgents fund {
        assertEq(agents.length, agentOwners.length);

        for (uint256 i = 0; i < agents.length; i++) {
            assertEq(agents[i].listingFee(), agentParameters[i].listingFee);
            assertEq(agents[i].owner(), agentOwners[i]);
            assertEq(agents[i].amountPerRound(), agentParameters[i].amountPerRound);
            assertEq(agents[i].name(), agentParameters[i].name);
            assertEq(token.balanceOf(address(agents[i])), agentParameters[i].amountPerRound);
        }
    }

    /// @notice Sellers cannot list more than maxArtifactCount
    function test_RevertWhen_ListMoreThanmaxArtifactCount()
        external
        fund
        createAgents
        sellersApproveToSwan
        addValidatorsToWhitelist
        registerOracles
        listArtifacts(sellers[0], marketParameters.maxArtifactCount, address(agents[0]))
    {
        // try to list more than max artifact count
        vm.prank(sellers[0]);
        vm.expectRevert(abi.encodeWithSelector(Swan.ArtifactLimitExceeded.selector, marketParameters.maxArtifactCount));
        swan.list("name", "symbol", "desc", 0.001 ether, address(agents[0]));
    }

    /// @notice Agent Owner cannot call purchase() in listing phase
    function test_RevertWhen_PurchaseInListingPhase()
        external
        fund
        createAgents
        sellersApproveToSwan
        addValidatorsToWhitelist
        registerOracles
        listArtifacts(sellers[0], marketParameters.maxArtifactCount, address(agents[0]))
    {
        // try to purchase in Listing Phase
        vm.prank(agentOwners[0]);
        vm.expectRevert(
            abi.encodeWithSelector(SwanAgent.InvalidPhase.selector, SwanAgent.Phase.Listing, SwanAgent.Phase.Buy)
        );
        agents[0].purchase();
    }

    /// @notice Seller cannot relist the artifact in the same round (for same or different agents)
    function test_RevertWhen_RelistInTheSameRound()
        external
        fund
        createAgents
        sellersApproveToSwan
        addValidatorsToWhitelist
        registerOracles
        listArtifacts(sellers[0], marketParameters.maxArtifactCount, address(agents[0]))
    {
        // get listed artifact
        address _artifactToFail = swan.getListedArtifacts(address(agents[0]), currRound)[0];

        vm.prank(sellers[0]);
        vm.expectRevert(abi.encodeWithSelector(Swan.RoundNotFinished.selector, _artifactToFail, currRound));
        swan.relist(_artifactToFail, address(agents[1]), 0.001 ether);
    }

    /// @notice Agent cannot purchase an artifact that is listed for another agent
    function test_RevertWhen_PurchaseByAnotherAgent()
        external
        fund
        createAgents
        sellersApproveToSwan
        addValidatorsToWhitelist
        registerOracles
        listArtifacts(sellers[0], marketParameters.maxArtifactCount, address(agents[0]))
    {
        address _agentToFail = agentOwners[0];
        SwanAgent _agent = agents[1];

        increaseTime(_agent.createdAt() + marketParameters.listingInterval, _agent, SwanAgent.Phase.Buy, 0);
        currPhase = SwanAgent.Phase.Buy;

        vm.expectRevert(abi.encodeWithSelector(Swan.Unauthorized.selector, _agentToFail));
        vm.prank(_agentToFail);
        _agent.purchase();
    }

    /// @notice Agent cannot spend more than amountPerRound per round
    function test_RevertWhen_PurchaseMoreThanAmountPerRound()
        external
        fund
        createAgents
        sellersApproveToSwan
        addValidatorsToWhitelist
        registerOracles
        listArtifacts(sellers[0], marketParameters.maxArtifactCount, address(agents[0]))
    {
        address _agentOwnerToFail = agentOwners[0];
        SwanAgent _agentToFail = agents[0];

        increaseTime(_agentToFail.createdAt() + marketParameters.listingInterval, _agentToFail, SwanAgent.Phase.Buy, 0);

        // get the listed artifacts as output
        address[] memory output = swan.getListedArtifacts(address(_agentToFail), currRound);
        bytes memory encodedOutput = abi.encode(output);

        vm.prank(_agentOwnerToFail);
        // make a purchase request
        _agentToFail.oraclePurchaseRequest(input, models);

        // respond
        safeRespond(generators[0], encodedOutput, 1);
        safeRespond(generators[1], encodedOutput, 1);

        // validate
        safeValidate(validators[0], 1);

        vm.prank(_agentOwnerToFail);
        vm.expectRevert(abi.encodeWithSelector(SwanAgent.BuyLimitExceeded.selector, artifactPrice * 2, amountPerRound));
        _agentToFail.purchase();
    }

    /// @notice Agent can purchase
    /// @dev Seller has to approve Swan
    /// @dev Agent must be in buy phase
    /// @dev Agent must have enough balance to purchase
    /// @dev artifact price must be less than amountPerRound
    function test_PurchaseAnArtifact()
        external
        fund
        createAgents
        sellersApproveToSwan
        addValidatorsToWhitelist
        registerOracles
        listArtifacts(sellers[0], marketParameters.maxArtifactCount, address(agents[0]))
    {
        // increase time to buy phase to be able to purchase
        increaseTime(agents[0].createdAt() + marketParameters.listingInterval, agents[0], SwanAgent.Phase.Buy, 0);

        safePurchase(agentOwners[0], agents[0], 1);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // 1. Transfer
        // 2. Transfer
        // 3. Transfer
        // 4. Transfer
        // 5. ArtifactSold (from Swan)
        // 6. Purchase (from SwanAgent)
        assertEq(entries.length, 6);

        // get the ArtifactSold event
        Vm.Log memory artifactSoldEvent = entries[entries.length - 2];

        // check event sig
        bytes32 eventSig = artifactSoldEvent.topics[0];
        assertEq(keccak256("ArtifactSold(address,address,address,uint256)"), eventSig);

        // decode params from event
        address _seller = abi.decode(abi.encode(artifactSoldEvent.topics[1]), (address));
        address _agent = abi.decode(abi.encode(artifactSoldEvent.topics[2]), (address));
        address _artifact = abi.decode(abi.encode(artifactSoldEvent.topics[3]), (address));
        uint256 _price = abi.decode(artifactSoldEvent.data, (uint256));

        assertEq(_agent, address(agents[0]));
        assertEq(_artifact, agents[0].inventory(0, 0));

        // get artifact details
        Swan.ArtifactListing memory artifactListing = swan.getListing(_artifact);

        assertEq(artifactListing.seller, _seller);
        assertEq(sellers[0], _seller);
        assertEq(artifactListing.agent, address(agents[0]));

        assertEq(uint8(artifactListing.status), uint8(Swan.ArtifactStatus.Sold));
        assertEq(artifactListing.price, _price);

        // emitter should be swan
        assertEq(artifactSoldEvent.emitter, address(swan));

        // try to purchase again
        vm.prank(agentOwners[0]);
        vm.expectRevert(abi.encodeWithSelector(SwanAgent.TaskAlreadyProcessed.selector));
        agents[0].purchase();
    }

    /// @dev Updates agent state
    function test_UpdateState()
        external
        fund
        createAgents
        sellersApproveToSwan
        addValidatorsToWhitelist
        registerOracles
        listArtifacts(sellers[0], marketParameters.maxArtifactCount, address(agents[0]))
    {
        address _agentOwner = agentOwners[0];
        SwanAgent _agent = agents[0];

        bytes memory newState = abi.encodePacked("0x", "after purchase");
        uint256 taskId = 1;

        increaseTime(_agent.createdAt() + marketParameters.listingInterval, _agent, SwanAgent.Phase.Buy, 0);
        safePurchase(_agentOwner, _agent, taskId);
        taskId++;

        increaseTime(
            _agent.createdAt() + marketParameters.listingInterval + marketParameters.buyInterval,
            _agent,
            SwanAgent.Phase.Withdraw,
            0
        );

        // try to send state request by another agent owner
        vm.prank(agentOwners[1]);
        vm.expectRevert(abi.encodeWithSelector(SwanAgent.Unauthorized.selector, agentOwners[1]));
        _agent.oracleStateRequest(input, models);

        vm.prank(_agentOwner);
        _agent.oracleStateRequest(input, models);

        safeRespond(generators[0], newState, taskId);
        safeRespond(generators[1], newState, taskId);

        safeValidate(validators[0], taskId);

        // try to update state by another agent owner
        vm.prank(agentOwners[1]);
        vm.expectRevert(abi.encodeWithSelector(SwanAgent.Unauthorized.selector, agentOwners[1]));
        _agent.updateState();

        vm.prank(_agentOwner);
        _agent.updateState();
        assertEq(_agent.state(), newState);
    }

    /// @notice Seller cannot list an artifact in withdraw phase
    function test_RevertWhen_ListInWithdrawPhase() external fund createAgents sellersApproveToSwan {
        SwanAgent _agent = agents[0];

        increaseTime(
            _agent.createdAt() + marketParameters.listingInterval + marketParameters.buyInterval,
            _agent,
            SwanAgent.Phase.Withdraw,
            0
        );
        currPhase = SwanAgent.Phase.Withdraw;

        checkRoundAndPhase(_agent, SwanAgent.Phase.Withdraw, 0);

        vm.prank(sellers[0]);
        vm.expectRevert(abi.encodeWithSelector(SwanAgent.InvalidPhase.selector, currPhase, SwanAgent.Phase.Listing));
        swan.list("name", "symbol", "desc", 0.01 ether, address(_agent));
    }

    /// @notice Agent Owner can setAmountPerRound in withdraw phase
    function test_SetAmountPerRound() external fund createAgents sellersApproveToSwan {
        SwanAgent _agent = agents[0];
        uint256 _newAmountPerRound = 2 ether;

        increaseTime(
            _agent.createdAt() + marketParameters.listingInterval + marketParameters.buyInterval,
            _agent,
            SwanAgent.Phase.Withdraw,
            0
        );

        vm.prank(agentOwners[0]);
        _agent.setAmountPerRound(_newAmountPerRound);
        assertEq(agent.amountPerRound(), _newAmountPerRound);
    }

    /// @notice Agent Owner cannot create agent with invalid listing fee
    /// @dev listingFee must be between 0 - 100
    function test_RevertWhen_CreateAgentWithInvalidListingFee() external fund {
        uint96 invalidFee = 150;

        vm.prank(agentOwners[0]);
        vm.expectRevert(abi.encodeWithSelector(SwanAgent.InvalidFee.selector, invalidFee));
        swan.createAgent(
            agentParameters[0].name, agentParameters[0].description, invalidFee, agentParameters[0].amountPerRound
        );
    }

    /// @notice Swan owner can set factories
    function test_SetFactories() external fund {
        SwanArtifactFactory _artifactFactory = new SwanArtifactFactory();
        SwanAgentFactory _agentFactory = new SwanAgentFactory();

        vm.prank(dria);
        swan.setFactories(address(_agentFactory), address(_artifactFactory));

        assertEq(address(swan.agentFactory()), address(_agentFactory));
        assertEq(address(swan.artifactFactory()), address(_artifactFactory));
    }

    /// @notice Seller cannot relist an artifact that is already purchased
    function test_RevertWhen_RelistAlreadyPurchasedArtifact()
        external
        fund
        createAgents
        sellersApproveToSwan
        addValidatorsToWhitelist
        registerOracles
        listArtifacts(sellers[0], marketParameters.maxArtifactCount, address(agents[0]))
    {
        address _agentOwner = agentOwners[0];
        SwanAgent _agent = agents[0];
        uint256 taskId = 1;

        // increase time to buy phase
        increaseTime(_agent.createdAt() + marketParameters.listingInterval, _agent, SwanAgent.Phase.Buy, 0);
        safePurchase(_agentOwner, _agent, taskId);

        uint256 listingPhaseOfTheSecondRound = _agent.createdAt() + marketParameters.listingInterval
            + marketParameters.buyInterval + marketParameters.withdrawInterval;
        increaseTime(listingPhaseOfTheSecondRound, _agent, SwanAgent.Phase.Listing, 1);

        // get artifact
        address _listedArtifactAddr = swan.getListedArtifacts(address(_agent), currRound)[0];
        assertEq(_agent.inventory(currRound, 0), _listedArtifactAddr);

        Swan.ArtifactListing memory artifact = swan.getListing(_listedArtifactAddr);

        // try to relist an artifact that is already purchased
        vm.prank(sellers[0]);
        vm.expectRevert(
            abi.encodeWithSelector(Swan.InvalidStatus.selector, artifact.status, Swan.ArtifactStatus.Listed)
        );
        swan.relist(_listedArtifactAddr, address(_agent), artifact.price);
    }

    /// @notice Seller cannot relist another seller's artifact
    function test_RevertWhen_RelistByAnotherSeller()
        external
        fund
        createAgents
        sellersApproveToSwan
        addValidatorsToWhitelist
        registerOracles
        listArtifacts(sellers[0], marketParameters.maxArtifactCount, address(agents[0]))
    {
        SwanAgent _agent = agents[0];
        address _listedArtifactAddr = swan.getListedArtifacts(address(_agent), currRound)[0];

        // increase time to the listing phase of the next round
        uint256 listingPhaseOfTheSecondRound = _agent.createdAt() + marketParameters.listingInterval
            + marketParameters.buyInterval + marketParameters.withdrawInterval;

        increaseTime(listingPhaseOfTheSecondRound, _agent, SwanAgent.Phase.Listing, 1);

        // try to relist an artifact by another seller
        vm.prank(sellers[1]);
        vm.expectRevert(abi.encodeWithSelector(Swan.Unauthorized.selector, sellers[1]));
        swan.relist(_listedArtifactAddr, address(_agent), 0.1 ether);
    }

    /// @notice Seller cannot relist another seller's artifact
    function test_RevertWhen_RelistMoreThanMaxArtifactCount()
        external
        fund
        createAgents
        sellersApproveToSwan
        addValidatorsToWhitelist
        registerOracles
        listArtifacts(sellers[0], marketParameters.maxArtifactCount, address(agents[0]))
    {
        SwanAgent _agent = agents[0];
        address _listedArtifactAddr = swan.getListedArtifacts(address(_agent), currRound)[0];

        // increase time to the listing phase of the next round
        uint256 listingPhaseOfTheSecondRound = _agent.createdAt() + marketParameters.listingInterval
            + marketParameters.buyInterval + marketParameters.withdrawInterval;

        increaseTime(listingPhaseOfTheSecondRound, _agent, SwanAgent.Phase.Listing, 1);

        // list maxArtifactCount artifacts
        for (uint256 i = 0; i < marketParameters.maxArtifactCount; i++) {
            vm.prank(sellers[1]);
            swan.list("name", "symbol", "desc", 0.0001 ether, address(_agent));
        }

        assertEq(swan.getListedArtifacts(address(_agent), 1).length, marketParameters.maxArtifactCount);

        // try to relist an artifact by seller
        vm.prank(sellers[0]);
        vm.expectRevert(abi.encodeWithSelector(Swan.ArtifactLimitExceeded.selector, marketParameters.maxArtifactCount));
        swan.relist(_listedArtifactAddr, address(_agent), marketParameters.minArtifactPrice);
    }

    /// @notice Seller can relist an artifact
    /// @dev Agent must be in Listing Phase
    function test_RelistArtifact()
        external
        fund
        createAgents
        sellersApproveToSwan
        addValidatorsToWhitelist
        registerOracles
        listArtifacts(sellers[0], marketParameters.maxArtifactCount, address(agents[0]))
    {
        SwanAgent _agent = agents[0];
        SwanAgent _agentToRelist = agents[1];

        address _listedArtifactAddr = swan.getListedArtifacts(address(_agent), currRound)[0];

        // increase time to the listing phase of the next round
        uint256 listingPhaseOfTheSecondRound = _agent.createdAt() + marketParameters.listingInterval
            + marketParameters.buyInterval + marketParameters.withdrawInterval;
        increaseTime(listingPhaseOfTheSecondRound, _agent, SwanAgent.Phase.Listing, 1);

        vm.prank(sellers[0]);
        vm.expectRevert(abi.encodeWithSelector(Swan.InvalidPrice.selector, 0));
        swan.relist(_listedArtifactAddr, address(_agentToRelist), 0);

        // try to relist an artifact by another seller
        vm.recordLogs();
        vm.prank(sellers[0]);
        swan.relist(_listedArtifactAddr, address(_agentToRelist), artifactPrice);

        // check the logs
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 4);
        // Transfer (from WETH)
        // Transfer (from WETH)
        // Transfer (from WETH)
        // ArtifactRelisted (from Swan)

        // get the event data
        Vm.Log memory artifactRelistedEvent = entries[entries.length - 1];

        bytes32 eventSig = artifactRelistedEvent.topics[0];
        assertEq(keccak256("ArtifactRelisted(address,address,address,uint256)"), eventSig);

        address _owner = abi.decode(abi.encode(artifactRelistedEvent.topics[1]), (address));
        address _expectedAgent = abi.decode(abi.encode(artifactRelistedEvent.topics[2]), (address));
        address _artifact = abi.decode(abi.encode(artifactRelistedEvent.topics[3]), (address));
        uint256 _price = abi.decode(artifactRelistedEvent.data, (uint256));

        assertEq(_owner, sellers[0]);
        assertEq(_expectedAgent, address(_agentToRelist));
        assertEq(_artifact, _listedArtifactAddr);
        assertEq(_price, artifactPrice);
    }

    /// @notice Seller cannot relist an artifact in Buy Phase
    function test_RevertWhen_RelistInBuyPhase()
        external
        fund
        createAgents
        sellersApproveToSwan
        addValidatorsToWhitelist
        registerOracles
        listArtifacts(sellers[0], marketParameters.maxArtifactCount, address(agents[0]))
    {
        SwanAgent _agent = agents[0];
        address _listedArtifactAddr = swan.getListedArtifacts(address(_agent), currRound)[0];

        // increase time to the buy phase of the second round
        uint256 buyPhaseOfTheSecondRound = _agent.createdAt() + marketParameters.listingInterval
            + marketParameters.buyInterval + marketParameters.withdrawInterval + marketParameters.listingInterval;

        increaseTime(buyPhaseOfTheSecondRound, _agent, SwanAgent.Phase.Buy, 1);
        currPhase = SwanAgent.Phase.Buy;

        // try to relist
        vm.expectRevert(abi.encodeWithSelector(SwanAgent.InvalidPhase.selector, currPhase, SwanAgent.Phase.Listing));
        vm.prank(sellers[0]);
        swan.relist(_listedArtifactAddr, address(_agent), artifactPrice);
    }

    ///  @notice Seller cannot relist an artifact in Withdraw Phase
    function test_RevertWhen_RelistInWithdrawPhase()
        external
        fund
        createAgents
        sellersApproveToSwan
        addValidatorsToWhitelist
        registerOracles
        listArtifacts(sellers[0], marketParameters.maxArtifactCount, address(agents[0]))
    {
        SwanAgent _agent = agents[0];
        address _listedArtifactAddr = swan.getListedArtifacts(address(_agent), currRound)[0];

        // increase time to the withdraw phase of the second round
        uint256 withdrawPhaseOfSecondRound = (2 * marketParameters.listingInterval) + (2 * marketParameters.buyInterval)
            + marketParameters.withdrawInterval + _agent.createdAt();

        increaseTime(withdrawPhaseOfSecondRound, _agent, SwanAgent.Phase.Withdraw, 1);
        currPhase = SwanAgent.Phase.Withdraw;

        // try to relist
        vm.expectRevert(abi.encodeWithSelector(SwanAgent.InvalidPhase.selector, currPhase, SwanAgent.Phase.Listing));
        vm.prank(sellers[0]);
        swan.relist(_listedArtifactAddr, address(_agent), artifactPrice);
    }

    function test_RevertWhen_SetMarketParametersWithInvalidFee() external fund {
        SwanMarketParameters memory newMarketParameters = SwanMarketParameters({
            withdrawInterval: 10 * 60,
            listingInterval: 12 * 60,
            buyInterval: 20 * 60,
            platformFee: 101, // fee cannot be more than 100
            maxArtifactCount: 100,
            timestamp: block.timestamp,
            minArtifactPrice: 0.00001 ether,
            maxAgentFee: 75
        });

        vm.prank(dria);
        // expectRevert(revertData, reverter)
        vm.expectRevert("Platform fee cannot exceed 100%", address(swan));
        swan.setMarketParameters(newMarketParameters);
    }

    /// @notice Swan owner can set market parameters
    /// @dev Only Swan owner can set market parameters
    function test_SetMarketParameters() external fund createAgents {
        // increase time to the withdraw phase
        increaseTime(
            agents[0].createdAt() + marketParameters.listingInterval + marketParameters.buyInterval,
            agents[0],
            SwanAgent.Phase.Withdraw,
            0
        );

        SwanMarketParameters memory newMarketParameters = SwanMarketParameters({
            withdrawInterval: 10 * 60,
            listingInterval: 12 * 60,
            buyInterval: 20 * 60,
            platformFee: 12,
            maxArtifactCount: 100,
            timestamp: block.timestamp,
            minArtifactPrice: 0.00001 ether,
            maxAgentFee: 75
        });

        vm.prank(dria);
        swan.setMarketParameters(newMarketParameters);

        SwanMarketParameters memory updatedParams = swan.getCurrentMarketParameters();
        assertEq(updatedParams.withdrawInterval, newMarketParameters.withdrawInterval);
        assertEq(updatedParams.listingInterval, newMarketParameters.listingInterval);
        assertEq(updatedParams.buyInterval, newMarketParameters.buyInterval);
        assertEq(updatedParams.platformFee, newMarketParameters.platformFee);
        assertEq(updatedParams.maxArtifactCount, newMarketParameters.maxArtifactCount);
        assertEq(updatedParams.timestamp, newMarketParameters.timestamp);
    }

    /// @notice Swan owner can set oracle parameters
    /// @dev Only Swan owner can set oracle parameters
    function test_SetOracleParameters() external fund createAgents {
        // increase time to the withdraw phase
        increaseTime(
            agents[0].createdAt() + marketParameters.listingInterval + marketParameters.buyInterval,
            agents[0],
            SwanAgent.Phase.Withdraw,
            0
        );

        LLMOracleTaskParameters memory newOracleParameters =
            LLMOracleTaskParameters({difficulty: 5, numGenerations: 3, numValidations: 4});

        vm.prank(dria);
        swan.setOracleParameters(newOracleParameters);

        LLMOracleTaskParameters memory updatedParams = swan.getOracleParameters();

        assertEq(updatedParams.difficulty, newOracleParameters.difficulty);
        assertEq(updatedParams.numGenerations, newOracleParameters.numGenerations);
        assertEq(updatedParams.numValidations, newOracleParameters.numValidations);
    }

    function test_RevertWhen_UpgradeByNonOwner() external fund {
        address _newImplementation = address(0x123);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, agentOwners[0]));
        vm.startPrank(agentOwners[0]);
        swan.upgradeToAndCall(_newImplementation, "");
    }
}
