// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {LLMOracleRegistry} from "@firstbatch/dria-oracle-contracts/LLMOracleRegistry.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {
    LLMOracleCoordinator, LLMOracleTaskParameters
} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";
import {BuyerAgent, BuyerAgentFactory} from "../src/BuyerAgent.sol";
import {SwanAssetFactory, SwanAsset} from "../src/SwanAsset.sol";
import {Swan, SwanMarketParameters} from "../src/Swan.sol";
import {WETH9} from "./WETH9.sol";
import {Vm} from "forge-std/Vm.sol";
import {Helper} from "./Helper.t.sol";

contract SwanTest is Helper {
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

        vm.label(address(swan), "Swan");
        vm.label(address(token), "WETH");
        vm.label(address(this), "SwanTest");
        vm.label(address(oracleRegistry), "LLMOracleRegistry");
        vm.label(address(oracleCoordinator), "LLMOracleCoordinator");
        vm.label(address(buyerAgentFactory), "BuyerAgentFactory");
        vm.label(address(swanAssetFactory), "SwanAssetFactory");
        _;
    }

    modifier fund() {
        scores = [1 ether];

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

    function test_Deployment() external deployment fund {
        assertEq(oracleCoordinator.platformFee(), fees.platformFee);
        assertEq(oracleCoordinator.generationFee(), fees.generationFee);
        assertEq(oracleCoordinator.validationFee(), fees.validationFee);

        assertEq(oracleRegistry.generatorStakeAmount(), stakes.generatorStakeAmount);
        assertEq(oracleRegistry.validatorStakeAmount(), stakes.validatorStakeAmount);
        assertEq(swan.owner(), dria);
    }

    function test_CreateBuyerAgents() external deployment createBuyers fund {
        assertEq(buyerAgents.length, buyerAgentOwners.length);

        for (uint256 i = 0; i < buyerAgents.length; i++) {
            assertEq(buyerAgents[i].feeRoyalty(), buyerAgentParameters[i].feeRoyalty);
            assertEq(buyerAgents[i].owner(), buyerAgentOwners[i]);
            assertEq(buyerAgents[i].amountPerRound(), buyerAgentParameters[i].amountPerRound);
            assertEq(buyerAgents[i].name(), buyerAgentParameters[i].name);
            assertEq(token.balanceOf(address(buyerAgents[i])), buyerAgentParameters[i].amountPerRound);
        }
    }

    /// @notice Sellers cannot list more than maxAssetCount
    function test_RevertWhen_ListMoreThanMaxAssetCount()
        external
        deployment
        fund
        createBuyers
        sellersApproveToSwan
        registerOracles
        listAssets(sellers[0], marketParameters.maxAssetCount, address(buyerAgents[0]))
    {
        // try to list more than max assets
        vm.prank(sellers[0]);
        vm.expectRevert(abi.encodeWithSelector(Swan.AssetLimitExceeded.selector, marketParameters.maxAssetCount));
        swan.list("name", "symbol", "desc", 0.001 ether, address(buyerAgents[0]));
    }

    /// @notice Buyer cannot call purchase() in sell phase
    function test_RevertWhen_PurchaseInSellPhase()
        external
        deployment
        fund
        createBuyers
        sellersApproveToSwan
        registerOracles
        listAssets(sellers[0], marketParameters.maxAssetCount, address(buyerAgents[0]))
    {
        // try to purchase
        vm.prank(buyerAgentOwners[0]);
        vm.expectRevert(
            abi.encodeWithSelector(BuyerAgent.InvalidPhase.selector, BuyerAgent.Phase.Sell, BuyerAgent.Phase.Buy)
        );
        buyerAgents[0].purchase();
    }

    /// @notice Seller cannot relist the asset in the same round (for same or different buyers)
    function test_RevertWhen_RelistInTheSameRound()
        external
        deployment
        fund
        createBuyers
        sellersApproveToSwan
        registerOracles
        listAssets(sellers[0], marketParameters.maxAssetCount, address(buyerAgents[0]))
    {
        // get the listed asset
        address assetToFail = swan.getListedAssets(address(buyerAgents[0]), currRound)[0];

        vm.prank(sellers[0]);
        vm.expectRevert(abi.encodeWithSelector(Swan.RoundNotFinished.selector, assetToFail, currRound));
        swan.relist(assetToFail, address(buyerAgents[1]), 0.001 ether);
    }

    /// @notice Buyer cannot purchase an asset that is not listed for him
    function test_RevertWhen_PurchaseByAnotherBuyer()
        external
        deployment
        fund
        createBuyers
        sellersApproveToSwan
        registerOracles
        listAssets(sellers[0], marketParameters.maxAssetCount, address(buyerAgents[0]))
    {
        address buyerToFail = buyerAgentOwners[0];
        BuyerAgent buyerAgent = buyerAgents[1];

        uint256 buyPhaseOfTheFirstRound = buyerAgent.createdAt() + marketParameters.sellInterval;
        vm.warp(buyPhaseOfTheFirstRound);
        currPhase = BuyerAgent.Phase.Buy;

        vm.expectRevert(abi.encodeWithSelector(Swan.Unauthorized.selector, buyerToFail));
        vm.prank(buyerToFail);
        buyerAgent.purchase();
    }

    /// @notice Buyer cannot spend more than amountPerRound per round
    function test_RevertWhen_PurchaseMoreThanAmountPerRound()
        external
        deployment
        fund
        createBuyers
        sellersApproveToSwan
        registerOracles
        listAssets(sellers[0], marketParameters.maxAssetCount, address(buyerAgents[0]))
    {
        address buyerToFail = buyerAgentOwners[0];
        BuyerAgent buyerAgentToFail = buyerAgents[0];

        vm.warp(buyerAgentToFail.createdAt() + marketParameters.sellInterval);
        currPhase = BuyerAgent.Phase.Buy;

        // get the listed assets as output
        address[] memory output = swan.getListedAssets(address(buyerAgentToFail), currRound);
        bytes memory encodedOutput = abi.encode(output);

        vm.prank(buyerToFail);
        // make a purchase request
        buyerAgentToFail.oraclePurchaseRequest(input, models);

        // respond
        safeRespond(generators[0], encodedOutput, 1);

        // validate
        safeValidate(validators[0], 1);

        vm.prank(buyerToFail);
        vm.expectRevert(abi.encodeWithSelector(BuyerAgent.BuyLimitExceeded.selector, assetPrice * 2, amountPerRound));
        buyerAgentToFail.purchase();
    }

    /// @notice Buyer can purchase
    /// @dev Seller has to approve Swan
    /// @dev Buyer Agent must be in buy phase
    /// @dev Buyer Agent must have enough balance to purchase
    /// @dev asset price must be less than amountPerRound
    function test_PurchaseAnAsset()
        external
        deployment
        fund
        createBuyers
        sellersApproveToSwan
        registerOracles
        listAssets(sellers[0], marketParameters.maxAssetCount, address(buyerAgents[0]))
    {
        // increase time to buy phase to be able to purchase
        vm.warp(buyerAgents[0].createdAt() + marketParameters.sellInterval);
        safePurchase(buyerAgentOwners[0], buyerAgents[0], 1);

        // 1. Transfer (from Swan)
        // 2. Transfer (from Swan)
        // 3. Transfer (from WETH9)
        // 4. Transfer (from WETH9)
        // 5. AssetSold
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 5);

        // get the AssetSold event
        Vm.Log memory assetSoldEvent = entries[entries.length - 1];

        // check event sig
        bytes32 eventSig = assetSoldEvent.topics[0];
        assertEq(keccak256("AssetSold(address,address,address,uint256)"), eventSig);

        // decode params from event
        address seller = abi.decode(abi.encode(assetSoldEvent.topics[1]), (address));
        address agent = abi.decode(abi.encode(assetSoldEvent.topics[2]), (address));
        address asset = abi.decode(abi.encode(assetSoldEvent.topics[3]), (address));
        uint256 price = abi.decode(assetSoldEvent.data, (uint256));

        assertEq(agent, address(buyerAgents[0]));
        assertEq(asset, buyerAgents[0].inventory(0, 0));

        // get asset details
        Swan.AssetListing memory assetListing = swan.getListing(asset);

        assertEq(assetListing.seller, seller);
        assertEq(assetListing.buyer, address(buyerAgents[0]));

        assertEq(uint8(assetListing.status), uint8(Swan.AssetStatus.Sold));
        assertEq(assetListing.price, price);

        // emitter should be swan
        assertEq(assetSoldEvent.emitter, address(swan));
    }

    function test_UpdateState()
        external
        deployment
        fund
        createBuyers
        sellersApproveToSwan
        registerOracles
        listAssets(sellers[0], marketParameters.maxAssetCount, address(buyerAgents[0]))
    {
        address buyerAgentOwner = buyerAgentOwners[0];
        BuyerAgent buyerAgent = buyerAgents[0];
        uint256 taskId = 1;

        vm.warp(buyerAgent.createdAt() + marketParameters.sellInterval);
        currPhase = BuyerAgent.Phase.Buy;

        safePurchase(buyerAgentOwners[0], buyerAgents[0], taskId);
        vm.warp(buyerAgents[0].createdAt() + marketParameters.sellInterval + marketParameters.buyInterval);
        taskId++;

        bytes memory newState = abi.encodePacked("0x", "after purchase");

        vm.prank(buyerAgentOwner);
        buyerAgents[0].oracleStateRequest(input, models);

        safeRespond(generators[0], newState, taskId);
        safeValidate(validators[0], taskId);

        vm.prank(buyerAgentOwner);
        buyerAgent.updateState();
        assertEq(buyerAgent.state(), newState);
    }

    /// @notice Seller cannot list an asset in withdraw phase
    function test_RevertWhen_ListInWithdrawPhase() external deployment fund createBuyers sellersApproveToSwan {
        uint256 withdrawPhase =
            buyerAgents[0].createdAt() + marketParameters.sellInterval + marketParameters.buyInterval;
        vm.warp(withdrawPhase);
        currPhase = BuyerAgent.Phase.Withdraw;

        vm.prank(sellers[0]);
        vm.expectRevert(abi.encodeWithSelector(BuyerAgent.InvalidPhase.selector, currPhase, BuyerAgent.Phase.Sell));
        swan.list("name", "symbol", "desc", 0.01 ether, address(buyerAgents[0]));
    }

    /// @notice Buyer Agent Owner can setAmountPerRound in withdraw phase
    function test_SetAmountPerRound() external deployment fund createBuyers sellersApproveToSwan {
        uint256 newAmountPerRound = 2 ether;

        vm.warp(buyerAgents[0].createdAt() + marketParameters.sellInterval + marketParameters.buyInterval);

        vm.prank(buyerAgentOwners[0]);
        buyerAgents[0].setAmountPerRound(newAmountPerRound);
        assertEq(buyerAgents[0].amountPerRound(), newAmountPerRound);
    }

    /// @notice Buyer Agent Owner cannot create buyer agent with invalid royalty
    /// @dev feeRoyalty must be between 0 - 100
    function test_RevertWhen_CreateBuyerWithInvalidRoyalty() external deployment fund {
        uint96 invalidRoyalty = 150;

        vm.prank(buyerAgentOwners[0]);
        vm.expectRevert(abi.encodeWithSelector(BuyerAgent.InvalidFee.selector, invalidRoyalty));
        swan.createBuyer(
            buyerAgentParameters[0].name,
            buyerAgentParameters[0].description,
            invalidRoyalty,
            buyerAgentParameters[0].amountPerRound
        );
    }

    /// @notice Swan owner can set factories
    function test_SetFactories() external deployment fund {
        SwanAssetFactory _swanAssetFactory = new SwanAssetFactory();
        BuyerAgentFactory _buyerAgentFactory = new BuyerAgentFactory();

        vm.prank(dria);
        swan.setFactories(address(_buyerAgentFactory), address(_swanAssetFactory));

        assertEq(address(swan.buyerAgentFactory()), address(_buyerAgentFactory));
        assertEq(address(swan.swanAssetFactory()), address(_swanAssetFactory));
    }

    /// @notice Seller cannot relist an asset that is already purchased
    function test_RevertWhen_RelistAlreadyPurchasedAsset()
        external
        deployment
        fund
        createBuyers
        sellersApproveToSwan
        registerOracles
        listAssets(sellers[0], marketParameters.maxAssetCount, address(buyerAgents[0]))
    {
        address buyer = buyerAgentOwners[0];
        BuyerAgent buyerAgent = buyerAgents[0];
        uint256 taskId = 1;

        // increase time to buy phase
        vm.warp(buyerAgent.createdAt() + marketParameters.sellInterval);
        safePurchase(buyer, buyerAgent, taskId);

        uint256 sellPhaseOfTheSecondRound =
            buyerAgent.createdAt() + marketParameters.buyInterval + marketParameters.withdrawInterval;
        vm.warp(sellPhaseOfTheSecondRound);

        // get the asset
        address listedAssetAddr = swan.getListedAssets(address(buyerAgent), currRound)[0];
        assertEq(buyerAgent.inventory(currRound, 0), listedAssetAddr);

        Swan.AssetListing memory asset = swan.getListing(listedAssetAddr);

        // try to relist the asset
        vm.prank(sellers[0]);
        vm.expectRevert(abi.encodeWithSelector(Swan.InvalidStatus.selector, asset.status, Swan.AssetStatus.Listed));
        swan.relist(listedAssetAddr, address(buyerAgent), asset.price);
    }

    /// @notice Seller cannot relist another seller's asset
    function test_RevertWhen_RelistByAnotherSeller()
        external
        deployment
        fund
        createBuyers
        sellersApproveToSwan
        registerOracles
        listAssets(sellers[0], marketParameters.maxAssetCount, address(buyerAgents[0]))
    {
        BuyerAgent buyerAgent = buyerAgents[0];
        address listedAssetAddr = swan.getListedAssets(address(buyerAgent), currRound)[0];

        // increase time to the sell phase of thze next round
        uint256 sellPhaseOfTheSecondRound = buyerAgent.createdAt() + marketParameters.sellInterval
            + marketParameters.buyInterval + marketParameters.withdrawInterval;
        vm.warp(sellPhaseOfTheSecondRound);

        // try to relist an asset by another seller
        vm.prank(sellers[1]);
        vm.expectRevert(abi.encodeWithSelector(Swan.Unauthorized.selector, sellers[1]));
        swan.relist(listedAssetAddr, address(buyerAgent), 0.1 ether);
    }

    /// @notice Seller can relist an asset
    /// @dev Buyer Agent must be in Sell Phase
    function test_RelistAsset()
        external
        deployment
        fund
        createBuyers
        sellersApproveToSwan
        registerOracles
        listAssets(sellers[0], marketParameters.maxAssetCount, address(buyerAgents[0]))
    {
        BuyerAgent buyerAgent = buyerAgents[0];
        BuyerAgent buyerAgentToRelist = buyerAgents[1];

        address listedAssetAddr = swan.getListedAssets(address(buyerAgent), currRound)[0];

        // increase time to the sell phase of the next round
        uint256 sellPhaseOfTheSecondRound = buyerAgent.createdAt() + marketParameters.sellInterval
            + marketParameters.buyInterval + marketParameters.withdrawInterval;
        vm.warp(sellPhaseOfTheSecondRound);

        // try to relist an asset by another seller
        vm.recordLogs();
        vm.prank(sellers[0]);
        swan.relist(listedAssetAddr, address(buyerAgentToRelist), assetPrice);

        // check the logs
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 4);
        // Transfer (from WETH)
        // Transfer (from WETH)
        // Transfer (from WETH)
        // AssetRelisted

        // get the event data
        Vm.Log memory assetRelistedEvent = entries[entries.length - 1];

        bytes32 eventSig = assetRelistedEvent.topics[0];
        assertEq(keccak256("AssetRelisted(address,address,address,uint256)"), eventSig);

        address owner = abi.decode(abi.encode(assetRelistedEvent.topics[1]), (address));
        address agent = abi.decode(abi.encode(assetRelistedEvent.topics[2]), (address));
        address asset = abi.decode(abi.encode(assetRelistedEvent.topics[3]), (address));
        uint256 price = abi.decode(assetRelistedEvent.data, (uint256));

        assertEq(owner, sellers[0]);
        assertEq(agent, address(buyerAgentToRelist));
        assertEq(asset, listedAssetAddr);
        assertEq(price, assetPrice);
    }

    /// @notice Seller cannot relist an asset in Buy Phase
    function test_RevertWhen_RelistInBuyPhase()
        external
        deployment
        fund
        createBuyers
        sellersApproveToSwan
        registerOracles
        listAssets(sellers[0], marketParameters.maxAssetCount, address(buyerAgents[0]))
    {
        BuyerAgent buyerAgent = buyerAgents[0];

        address listedAssetAddr = swan.getListedAssets(address(buyerAgent), currRound)[0];

        // increase time to the buy phase of the second round
        uint256 buyPhaseOfTheSecondRound = buyerAgent.createdAt() + 2 * marketParameters.sellInterval
            + marketParameters.buyInterval + marketParameters.withdrawInterval;
        vm.warp(buyPhaseOfTheSecondRound);
        currPhase = BuyerAgent.Phase.Buy;

        // check the current phase
        (, BuyerAgent.Phase _phase,) = buyerAgent.getRoundPhase();
        require(uint8(currPhase) == uint8(_phase), "Phase is not 'Buy'");

        // try to relist
        vm.expectRevert(abi.encodeWithSelector(BuyerAgent.InvalidPhase.selector, currPhase, BuyerAgent.Phase.Sell));
        vm.prank(sellers[0]);
        swan.relist(listedAssetAddr, address(buyerAgent), assetPrice);
    }

    ///  @notice Seller cannot relist an asset in Withdraw Phase
    function test_RevertWhen_RelistInWithdrawPhase()
        external
        deployment
        fund
        createBuyers
        sellersApproveToSwan
        registerOracles
        listAssets(sellers[0], marketParameters.maxAssetCount, address(buyerAgents[0]))
    {
        BuyerAgent buyerAgent = buyerAgents[0];
        address listedAssetAddr = swan.getListedAssets(address(buyerAgent), currRound)[0];

        // increase time to the withdraw phase of the second round
        uint256 withdrawPhaseOfSecondRound = 2 * marketParameters.buyInterval + 2 * marketParameters.sellInterval
            + marketParameters.withdrawInterval + buyerAgent.createdAt();
        vm.warp(withdrawPhaseOfSecondRound);
        currPhase = BuyerAgent.Phase.Withdraw;

        // try to relist
        vm.expectRevert(abi.encodeWithSelector(BuyerAgent.InvalidPhase.selector, currPhase, BuyerAgent.Phase.Sell));
        vm.prank(sellers[0]);
        swan.relist(listedAssetAddr, address(buyerAgent), assetPrice);
    }

    /// @notice Swan owner can set market parameters
    /// @dev Only Swan owner can set market parameters
    function test_SetMarketParameters() external deployment fund createBuyers {
        // increase time to the withdraw phase
        vm.warp(buyerAgents[0].createdAt() + marketParameters.buyInterval + marketParameters.sellInterval);

        SwanMarketParameters memory newMarketParameters = SwanMarketParameters({
            withdrawInterval: 10 * 60,
            sellInterval: 12 * 60,
            buyInterval: 20 * 60,
            platformFee: 12,
            maxAssetCount: 100,
            timestamp: block.timestamp,
            minAssetPrice: 0.00001 ether,
            maxBuyerAgentFee: 75
        });

        vm.prank(dria);
        swan.setMarketParameters(newMarketParameters);

        SwanMarketParameters memory updatedParams = swan.getCurrentMarketParameters();
        assertEq(updatedParams.withdrawInterval, newMarketParameters.withdrawInterval);
        assertEq(updatedParams.sellInterval, newMarketParameters.sellInterval);
        assertEq(updatedParams.buyInterval, newMarketParameters.buyInterval);
        assertEq(updatedParams.platformFee, newMarketParameters.platformFee);
        assertEq(updatedParams.maxAssetCount, newMarketParameters.maxAssetCount);
        assertEq(updatedParams.timestamp, newMarketParameters.timestamp);
    }

    /// @notice Swan owner can set oracle parameters
    /// @dev Only Swan owner can set oracle parameters
    function test_SetOracleParameters() external deployment fund createBuyers {
        // increase time to the withdraw phase
        vm.warp(buyerAgents[0].createdAt() + marketParameters.buyInterval + marketParameters.sellInterval);

        LLMOracleTaskParameters memory newOracleParameters =
            LLMOracleTaskParameters({difficulty: 5, numGenerations: 3, numValidations: 4});

        vm.prank(dria);
        swan.setOracleParameters(newOracleParameters);

        LLMOracleTaskParameters memory updatedParams = swan.getOracleParameters();

        assertEq(updatedParams.difficulty, newOracleParameters.difficulty);
        assertEq(updatedParams.numGenerations, newOracleParameters.numGenerations);
        assertEq(updatedParams.numValidations, newOracleParameters.numValidations);
    }
}
