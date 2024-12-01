// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Vm} from "forge-std/Vm.sol";
import {Test} from "forge-std/Test.sol";

import {WETH9} from "./WETH9.sol";
import {LLMOracleRegistry, LLMOracleKind} from "@firstbatch/dria-oracle-contracts/LLMOracleRegistry.sol";
import {LLMOracleCoordinator} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";
import {SwanMarketParameters} from "../src/SwanManager.sol";
import {LLMOracleTaskParameters} from "@firstbatch/dria-oracle-contracts/LLMOracleTask.sol";
import {BuyerAgent, BuyerAgentFactory} from "../src/BuyerAgent.sol";
import {SwanAssetFactory} from "../src/SwanAsset.sol";
import {BuyerAgent} from "../src/BuyerAgent.sol";
import {Swan} from "../src/Swan.sol";
import {Stakes, Fees} from "../script/HelperConfig.s.sol";

// CREATED TO PREVENT CODE DUPLICATION IN TESTS
abstract contract Helper is Test {
    /// @dev Parameters for the buyer agent deployment
    struct BuyerAgentParameters {
        string name;
        string description;
        uint96 feeRoyalty;
        uint256 amountPerRound;
    }

    bytes32 public constant ORACLE_PROTOCOL = "test/0.0.1";

    Stakes stakes;
    Fees fees;

    address dria;
    address[] buyerAgentOwners;
    address[] sellers;

    address[] generators;
    address[] validators;

    uint256 currRound;
    BuyerAgent.Phase currPhase;

    BuyerAgentParameters[] buyerAgentParameters;
    LLMOracleTaskParameters oracleParameters;
    SwanMarketParameters marketParameters;

    LLMOracleCoordinator oracleCoordinator;
    LLMOracleRegistry oracleRegistry;
    BuyerAgentFactory buyerAgentFactory;
    SwanAssetFactory swanAssetFactory;
    BuyerAgent[] buyerAgents;

    WETH9 token;
    Swan swan;

    bytes input = "0x";
    bytes models = "0x";
    bytes metadata = "0x";

    uint256 assetPrice = 0.01 ether;
    uint256 amountPerRound = 0.015 ether;
    uint8 feeRoyalty = 2;

    // Default scores for validation
    uint256[] scores = [1, 5, 70];

    /// @notice The given nonce is not a valid proof-of-work.
    error InvalidNonceFromHelperTest(uint256 taskId, uint256 nonce, uint256 computedNonce, address caller);

    // Set parameters for the test
    function setUp() public {
        dria = vm.addr(1);
        validators = [vm.addr(2), vm.addr(3), vm.addr(4)];
        generators = [vm.addr(5), vm.addr(6), vm.addr(7)];
        buyerAgentOwners = [vm.addr(8), vm.addr(9)];
        sellers = [vm.addr(10), vm.addr(11)];

        oracleParameters = LLMOracleTaskParameters({difficulty: 1, numGenerations: 1, numValidations: 1});
        marketParameters = SwanMarketParameters({
            withdrawInterval: 300, // 5 minutes
            sellInterval: 360,
            buyInterval: 600,
            platformFee: 2, // percentage
            maxAssetCount: 3,
            timestamp: block.timestamp,
            minAssetPrice: 0.00001 ether,
            maxBuyerAgentFee: 75 // percentage
        });

        stakes = Stakes({generatorStakeAmount: 0.01 ether, validatorStakeAmount: 0.01 ether});
        fees = Fees({platformFee: 0.0001 ether, generatorFee: 0.0002 ether, validatorFee: 0.00003 ether});

        for (uint96 i = 0; i < buyerAgentOwners.length; i++) {
            buyerAgentParameters.push(
                BuyerAgentParameters({
                    name: string.concat("BuyerAgent", vm.toString(uint256(i))),
                    description: "description of the buyer agent",
                    feeRoyalty: feeRoyalty,
                    amountPerRound: amountPerRound
                })
            );

            vm.label(buyerAgentOwners[i], string.concat("BuyerAgentOwner#", vm.toString(i + 1)));
        }
        vm.label(dria, "Dria");
        vm.label(address(this), "Helper");
    }

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Register generators and validators
    modifier registerOracles() {
        for (uint256 i = 0; i < generators.length; i++) {
            // approve the stake for the generator
            vm.startPrank(generators[i]);
            token.approve(address(oracleRegistry), stakes.generatorStakeAmount + stakes.validatorStakeAmount);

            // register the generator oracle
            oracleRegistry.register(LLMOracleKind.Generator);
            vm.stopPrank();

            assertTrue(oracleRegistry.isRegistered(generators[i], LLMOracleKind.Generator));
            vm.label(generators[i], string.concat("Generator#", vm.toString(i + 1)));
        }

        for (uint256 i = 0; i < validators.length; i++) {
            // approve the stake for the validator
            vm.startPrank(validators[i]);
            token.approve(address(oracleRegistry), stakes.validatorStakeAmount);

            // register the validator oracle
            oracleRegistry.register(LLMOracleKind.Validator);
            vm.stopPrank();

            assertTrue(oracleRegistry.isRegistered(validators[i], LLMOracleKind.Validator));
            vm.label(validators[i], string.concat("Validator#", vm.toString(i + 1)));
        }
        _;
    }

    /// @notice Create buyers by using buyerAgentOwners and buyerAgentParameters
    modifier createBuyers() virtual {
        for (uint256 i = 0; i < buyerAgentOwners.length; i++) {
            // fund buyer agent owner
            deal(address(token), buyerAgentOwners[i], 3 ether);

            // start recording event info
            vm.recordLogs();

            vm.startPrank(buyerAgentOwners[i]);
            BuyerAgent buyerAgent = swan.createBuyer(
                buyerAgentParameters[i].name,
                buyerAgentParameters[i].description,
                buyerAgentParameters[i].feeRoyalty,
                buyerAgentParameters[i].amountPerRound
            );

            // get recorded logs
            Vm.Log[] memory entries = vm.getRecordedLogs();

            // 1. OwnershipTransferred (from Ownable)
            // 2. Approval (from BuyerAgent constructor to approve coordinator)
            // 3. Approval (from BuyerAgent constructor to approve swan)
            // 4. BuyerCreated (from Swan)
            assertEq(entries.length, 4);

            // get the BuyerCreated event
            Vm.Log memory buyerCreatedEvent = entries[entries.length - 1];

            // Log is a struct that holds the event info:
            //   struct Log {
            //      bytes32[] topics;
            //      bytes data;
            //      address emitter;
            //   }

            // topics[0] is the event signature
            // topics[1] is the first indexed parameter
            // topics[2] is the second indexed parameter
            // topics[3] is the third indexed parameter
            // data holds non-indexed parameters (bytes)
            // emitter is the address of the contract that emitted the event

            // get event sig
            bytes32 eventSig = buyerCreatedEvent.topics[0];
            assertEq(keccak256("BuyerCreated(address,address)"), eventSig);

            // decode owner & agent address from topics
            address owner = abi.decode(abi.encode(buyerCreatedEvent.topics[1]), (address));
            address agent = abi.decode(abi.encode(buyerCreatedEvent.topics[2]), (address));

            // emitter should be swan
            assertEq(buyerCreatedEvent.emitter, address(swan));

            // all guuud
            buyerAgents.push(BuyerAgent(agent));

            vm.label(address(buyerAgents[i]), string.concat("BuyerAgent#", vm.toString(i + 1)));

            // transfer token to agent
            token.transfer(address(buyerAgent), amountPerRound);
            assertEq(token.balanceOf(address(buyerAgent)), amountPerRound);
            vm.stopPrank();
        }

        assertEq(buyerAgents.length, buyerAgentOwners.length);
        currPhase = BuyerAgent.Phase.Sell;
        _;
    }

    /// @notice Sellers approve swan
    modifier sellersApproveToSwan() {
        for (uint256 i = 0; i < sellers.length; i++) {
            vm.prank(sellers[i]);
            token.approve(address(swan), 1 ether);
            assertEq(token.allowance(sellers[i], address(swan)), 1 ether);
            vm.label(sellers[i], string.concat("Seller#", vm.toString(i + 1)));
        }
        _;
    }

    /// @notice Listing assets with the given params.
    /// @param seller Seller of the asset.
    /// @param assetCount Number of assets that will be listed.
    /// @param buyerAgent Agent that assets will be list for.
    modifier listAssets(address seller, uint256 assetCount, address buyerAgent) {
        vm.startPrank(seller);
        for (uint256 i = 0; i < assetCount; i++) {
            swan.list(
                string.concat("SwanAsset#", vm.toString(i)),
                string.concat("SA#", vm.toString(i)),
                "description or the swan asset",
                assetPrice,
                buyerAgent
            );
        }
        vm.stopPrank();

        // check if assets listed
        address[] memory listedAssets = swan.getListedAssets(buyerAgent, currRound);
        assertEq(listedAssets.length, assetCount);
        _;
    }

    /// @dev Sets oracle parameters
    modifier setOracleParameters(uint8 _difficulty, uint40 _numGenerations, uint40 _numValidations) {
        oracleParameters.difficulty = _difficulty;
        oracleParameters.numGenerations = _numGenerations;
        oracleParameters.numValidations = _numValidations;

        assertEq(oracleParameters.difficulty, _difficulty);
        assertEq(oracleParameters.numGenerations, _numGenerations);
        assertEq(oracleParameters.numValidations, _numValidations);
        _;
    }

    // @notice Mines a valid nonce until the hash meets the difficulty target.
    function mineNonce(address responder, uint256 taskId) internal view returns (uint256) {
        // get the task
        (address requester,,,,,,,,) = oracleCoordinator.requests(taskId);
        uint256 target = type(uint256).max >> oracleParameters.difficulty;

        for (uint256 nonce; nonce < type(uint256).max; nonce++) {
            bytes memory message = abi.encodePacked(taskId, input, requester, responder, nonce);
            uint256 digest = uint256(keccak256(message));

            if (uint256(digest) < target) {
                return nonce;
            }
        }
    }

    /// @notice Makes a request to Oracle Coordinator
    modifier safeRequest(address requester, uint256 taskId) {
        (uint256 _total, uint256 _generator, uint256 _validator) = oracleCoordinator.getFee(oracleParameters);

        vm.startPrank(requester); // simulate transaction from requester
        token.approve(address(oracleCoordinator), _total);
        oracleCoordinator.request(ORACLE_PROTOCOL, input, models, oracleParameters);
        vm.stopPrank();

        // check request params
        (
            address _requester,
            ,
            ,
            ,
            uint256 _generatorFee,
            uint256 _validatorFee,
            ,
            bytes memory _input,
            bytes memory _models
        ) = oracleCoordinator.requests(taskId);

        assertEq(_requester, requester);
        assertEq(_input, input);
        assertEq(_models, models);
        assertEq(_generatorFee, _generator);
        assertEq(_validatorFee, _validator);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Responds to task
    /// @param responder Responder address
    /// @param output Output of the task
    /// @param taskId Task Id
    function safeRespond(address responder, bytes memory output, uint256 taskId) internal {
        uint256 nonce = mineNonce(responder, taskId);
        vm.prank(responder);
        oracleCoordinator.respond(taskId, nonce, output, metadata);
    }

    /// @notice Validates the task
    /// @param validator Validator address
    /// @param taskId Task Id
    function safeValidate(address validator, uint256 taskId) internal {
        uint256 nonce = mineNonce(validator, taskId);
        vm.prank(validator);
        oracleCoordinator.validate(taskId, nonce, scores, metadata);
    }

    /// @notice Makes a purchase request to Oracle Coordinator
    function safePurchase(address buyer, BuyerAgent buyerAgent, uint256 taskId) public {
        address[] memory listedAssets = swan.getListedAssets(address(buyerAgent), currRound);

        // get the listed assets as output
        address[] memory output = new address[](1);
        output[0] = listedAssets[0];
        assertEq(output.length, 1);

        vm.prank(buyer);
        buyerAgent.oraclePurchaseRequest(input, models);

        bytes memory encodedOutput = abi.encode((address[])(output));

        // respond
        safeRespond(generators[0], encodedOutput, taskId);

        // validate
        safeValidate(validators[0], taskId);

        assert(token.balanceOf(address(buyerAgent)) > assetPrice);

        // purchase and check event logs
        vm.recordLogs();
        vm.prank(buyer);
        buyerAgent.purchase();
    }

    /// @dev Sets market parameters
    function setMarketParameters(SwanMarketParameters memory newMarketParameters) public {
        vm.prank(dria);
        swan.setMarketParameters(newMarketParameters);

        // get new params
        SwanMarketParameters memory _newMarketParameters = swan.getCurrentMarketParameters();
        assertEq(_newMarketParameters.sellInterval, newMarketParameters.sellInterval);
        assertEq(_newMarketParameters.buyInterval, newMarketParameters.buyInterval);
        assertEq(_newMarketParameters.withdrawInterval, newMarketParameters.withdrawInterval);
    }

    /// @dev Checks if the round, phase and timeRemaining is correct
    function checkRoundAndPhase(BuyerAgent agent, BuyerAgent.Phase phase, uint256 round)
        public
        view
        returns (uint256)
    {
        // get the current round and phase of buyer agent
        (uint256 _currRound, BuyerAgent.Phase _currPhase,) = agent.getRoundPhase();
        assertEq(uint8(_currPhase), uint8(phase));
        assertEq(uint8(_currRound), uint8(round));

        // return the last timestamp to use in test
        return block.timestamp;
    }
}
