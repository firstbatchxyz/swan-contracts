// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Vm} from "forge-std/Vm.sol";
import {Test} from "forge-std/Test.sol";

import {WETH9} from "./contracts/WETH9.sol";
import {LLMOracleRegistry, LLMOracleKind} from "@firstbatch/dria-oracle-contracts/LLMOracleRegistry.sol";
import {LLMOracleCoordinator} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";
import {SwanMarketParameters} from "../src/SwanManager.sol";
import {LLMOracleTaskParameters} from "@firstbatch/dria-oracle-contracts/LLMOracleTask.sol";
import {SwanAgent, SwanAgentFactory} from "../src/SwanAgent.sol";
import {SwanArtifactFactory} from "../src/SwanArtifact.sol";
import {Swan} from "../src/Swan.sol";
import {Stakes, Fees} from "../script/HelperConfig.s.sol";

// CREATED TO PREVENT CODE DUPLICATION IN TESTS
abstract contract Helper is Test {
    /// @dev Parameters for the agent deployment
    struct AgentParameters {
        string name;
        string description;
        uint96 feeRoyalty;
        uint256 amountPerRound;
    }

    bytes32 public constant ORACLE_PROTOCOL = "test/0.0.1";

    Stakes stakes;
    Fees fees;

    address dria;
    address[] agentOwners;
    address[] sellers;

    address[] generators;
    address[] validators;

    uint256 currRound;
    SwanAgent.Phase currPhase;

    AgentParameters[] agentParameters;
    LLMOracleTaskParameters oracleParameters;
    SwanMarketParameters marketParameters;

    LLMOracleCoordinator oracleCoordinator;
    LLMOracleRegistry oracleRegistry;

    SwanAgentFactory agentFactory;
    SwanArtifactFactory artifactFactory;
    SwanAgent[] agents;

    SwanAgent agent;
    address agentOwner;

    WETH9 token;
    Swan swan;

    bytes input = "0x";
    bytes models = "0x";
    bytes metadata = "0x";

    uint256 artifactPrice = 0.01 ether;
    uint256 amountPerRound = 0.015 ether;
    uint8 feeRoyalty = 2;

    /// @dev Default scores for validation
    uint256[] scores = [1, 5, 70];

    uint256 public minRegistrationTime = 1 days; // in seconds
    uint256 public minScore = 1;
    uint256 public maxScore = type(uint8).max; // 255

    /// @notice The given nonce is not a valid proof-of-work.
    error InvalidNonceFromHelperTest(uint256 taskId, uint256 nonce, uint256 computedNonce, address caller);

    // @dev Set parameters for the test
    function setUp() public deployment {
        dria = vm.addr(1);
        validators = [vm.addr(2), vm.addr(3), vm.addr(4)];
        generators = [vm.addr(5), vm.addr(6), vm.addr(7)];
        agentOwners = [vm.addr(8), vm.addr(9)];
        sellers = [vm.addr(10), vm.addr(11)];

        oracleParameters = LLMOracleTaskParameters({difficulty: 1, numGenerations: 2, numValidations: 1});
        marketParameters = SwanMarketParameters({
            withdrawInterval: 300, // 5 minutes
            listingInterval: 360,
            buyInterval: 600,
            platformFee: 2, // percentage
            maxArtifactCount: 3,
            timestamp: block.timestamp,
            minArtifactPrice: 0.00001 ether,
            maxAgentFee: 75 // percentage
        });

        stakes = Stakes({generatorStakeAmount: 0.01 ether, validatorStakeAmount: 0.01 ether});
        fees = Fees({platformFee: 1, generationFee: 0.0002 ether, validationFee: 0.00003 ether});

        for (uint96 i = 0; i < agentOwners.length; i++) {
            agentParameters.push(
                AgentParameters({
                    name: string.concat("AIAgent", vm.toString(uint256(i))),
                    description: "description of the AI agent",
                    feeRoyalty: feeRoyalty,
                    amountPerRound: amountPerRound
                })
            );

            vm.label(agentOwners[i], string.concat("AgentOwner#", vm.toString(i + 1)));
        }
        vm.label(dria, "Dria");
        vm.label(address(this), "Helper");
    }

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier deployment() {
        _;
        // deploy WETH9
        token = new WETH9();
        bytes memory wethCode = address(token).code;
        address targetAddr = 0x4200000000000000000000000000000000000006;
        // sets the bytecode of the target address to the WETH9 contract
        vm.etch(targetAddr, wethCode);
        token = WETH9(payable(targetAddr));
        assertEq(address(token), targetAddr);

        // deploy llm contracts
        vm.startPrank(dria);

        address registryProxy = Upgrades.deployUUPSProxy(
            "LLMOracleRegistry.sol",
            abi.encodeCall(
                LLMOracleRegistry.initialize,
                (stakes.generatorStakeAmount, stakes.validatorStakeAmount, address(token), minRegistrationTime)
            )
        );
        oracleRegistry = LLMOracleRegistry(registryProxy);

        address coordinatorProxy = Upgrades.deployUUPSProxy(
            "LLMOracleCoordinator.sol",
            abi.encodeCall(
                LLMOracleCoordinator.initialize,
                (
                    address(oracleRegistry),
                    address(token),
                    fees.platformFee,
                    fees.generationFee,
                    fees.validationFee,
                    minScore,
                    maxScore
                )
            )
        );
        oracleCoordinator = LLMOracleCoordinator(coordinatorProxy);

        // deploy factory contracts
        agentFactory = new SwanAgentFactory();
        artifactFactory = new SwanArtifactFactory();

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
                    address(agentFactory),
                    address(artifactFactory)
                )
            )
        );
        swan = Swan(swanProxy);
        vm.stopPrank();

        vm.label(address(swan), "Swan");
        vm.label(address(token), "WETH");
        vm.label(address(oracleRegistry), "LLMOracleRegistry");
        vm.label(address(oracleCoordinator), "LLMOracleCoordinator");
        vm.label(address(agentFactory), "SwanAgentFactory");
        vm.label(address(artifactFactory), "SwanArtifactFactory");
    }

    /// @notice Add validators to the whitelist.
    modifier addValidatorsToWhitelist() {
        vm.prank(dria);
        oracleRegistry.addToWhitelist(validators);

        for (uint256 i; i < validators.length; i++) {
            vm.assertTrue(oracleRegistry.isWhitelisted(validators[i]));
        }
        _;
    }

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

    /// @notice Create agents by using agentOwners and agentParameters
    modifier createAgents() virtual {
        for (uint256 i = 0; i < agentOwners.length; i++) {
            // fund agent owner
            deal(address(token), agentOwners[i], 3 ether);

            // start recording event info
            vm.recordLogs();

            vm.startPrank(agentOwners[i]);
            SwanAgent AIagent = swan.createAgent(
                agentParameters[i].name,
                agentParameters[i].description,
                agentParameters[i].feeRoyalty,
                agentParameters[i].amountPerRound
            );

            // get recorded logs
            Vm.Log[] memory entries = vm.getRecordedLogs();

            // 1. OwnershipTransferred (from Ownable)
            // 2. Approval (from AIAgent constructor to approve coordinator)
            // 3. Approval (from AIAgent constructor to approve swan)
            // 4. AIAgentCreated (from Swan)
            assertEq(entries.length, 4);

            // get the AIAgentCreated event
            Vm.Log memory agentCreatedEvent = entries[entries.length - 1];

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
            bytes32 eventSig = agentCreatedEvent.topics[0];
            assertEq(keccak256("AIAgentCreated(address,address)"), eventSig);

            // decode owner & agent address from topics
            address _owner = abi.decode(abi.encode(agentCreatedEvent.topics[1]), (address));
            address _agent = abi.decode(abi.encode(agentCreatedEvent.topics[2]), (address));

            assertEq(_owner, agentOwners[i]);
            // emitter should be swan
            assertEq(agentCreatedEvent.emitter, address(swan));

            // all guuud
            agents.push(SwanAgent(_agent));

            vm.label(address(agents[i]), string.concat("AIAgent#", vm.toString(i + 1)));

            // transfer token to agent
            token.transfer(address(AIagent), amountPerRound);
            assertEq(token.balanceOf(address(AIagent)), amountPerRound);
            vm.stopPrank();
        }

        assertEq(agents.length, agentOwners.length);
        currPhase = SwanAgent.Phase.Listing;

        agent = agents[0];
        agentOwner = agentOwners[0];
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

    /// @notice Listing artifacts with the given params.
    /// @param seller Seller of the artifact.
    /// @param artifactCount Number of artifacts that will be listed.
    /// @param _agent Agent that artifacts will be list for.
    modifier listArtifacts(address seller, uint256 artifactCount, address _agent) {
        uint256 invalidPrice = SwanAgent(_agent).amountPerRound();

        vm.expectRevert(abi.encodeWithSelector(Swan.InvalidPrice.selector, invalidPrice));
        vm.prank(seller);
        swan.list("Artifact", "SA", "description or the swan artifact", invalidPrice, _agent);

        vm.recordLogs();
        for (uint256 i = 0; i < artifactCount; i++) {
            vm.prank(seller);
            swan.list(
                string.concat("Artifact#", vm.toString(i)),
                string.concat("SA#", vm.toString(i)),
                "description or the swan artifact",
                artifactPrice,
                _agent
            );

            // From Artifact' constructor
            // 1. OwnershipTransferred (from Ownable)
            // 2. Transfer (_safeMint() related)
            // 3. ApprovalForAll

            // From transferRoyalties()
            // 4. Transfer (WETH9: royalty transfer to Swan)
            // 5. Transfer (WETH9: royalty transfer to AI Agent)
            // 6. Transfer (WETH9: royalty transfer to dria)

            // From Swan
            // 7. ArtifactListed
            Vm.Log[] memory entries = vm.getRecordedLogs();
            assertEq(entries.length, 7);

            // get the ArtifactListed event
            Vm.Log memory artifactListedEvent = entries[entries.length - 1];

            // check event sig
            bytes32 eventSig = artifactListedEvent.topics[0];
            assertEq(keccak256("ArtifactListed(address,address,uint256)"), eventSig);

            // decode params from event
            address _seller = abi.decode(abi.encode(artifactListedEvent.topics[1]), (address));
            address artifact = abi.decode(abi.encode(artifactListedEvent.topics[2]), (address));
            uint256 price = abi.decode(artifactListedEvent.data, (uint256));

            // get artifact details
            Swan.ArtifactListing memory artifactListing = swan.getListing(artifact);

            assertEq(artifactListing.seller, _seller);
            assertEq(seller, _seller);
            assertEq(artifactListing.agent, address(agent));

            assertEq(uint8(artifactListing.status), uint8(Swan.ArtifactStatus.Listed));
            assertEq(artifactListing.price, price);

            // emitter should be swan
            assertEq(artifactListedEvent.emitter, address(swan));
        }

        // check if artifacts listed
        address[] memory listedArtifacts = swan.getListedArtifacts(_agent, currRound);
        assertEq(listedArtifacts.length, artifactCount);
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

        return 0; // should never reach here
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

    /// @notice Increases time in the test
    function increaseTime(uint256 timeInseconds, SwanAgent _agent, SwanAgent.Phase expectedPhase, uint256 expectedRound)
        public
    {
        vm.warp(timeInseconds + 1);

        // get the current round and phase of agent
        (uint256 _currRound, SwanAgent.Phase _currPhase,) = _agent.getRoundPhase();
        assertEq(uint8(_currPhase), uint8(expectedPhase));
        assertEq(uint8(_currRound), uint8(expectedRound));
    }

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
    function safePurchase(address _agentOwner, SwanAgent _agent, uint256 taskId) public {
        address[] memory listedArtifacts = swan.getListedArtifacts(address(_agent), currRound);

        // get the listed artifacts as output
        address[] memory output = new address[](1);
        output[0] = listedArtifacts[0];
        assertEq(output.length, 1);

        vm.prank(_agentOwner);
        _agent.oraclePurchaseRequest(input, models);

        bytes memory encodedOutput = abi.encode((address[])(output));

        // respond
        safeRespond(generators[0], encodedOutput, taskId);
        safeRespond(generators[1], encodedOutput, taskId);

        // validate
        safeValidate(validators[0], taskId);

        assertGe(token.balanceOf(address(_agent)), artifactPrice);

        // purchase and check event logs
        vm.recordLogs();
        vm.prank(_agentOwner);
        _agent.purchase();
    }

    /// @dev Sets market parameters
    function setMarketParameters(SwanMarketParameters memory newMarketParameters) public {
        vm.prank(dria);
        swan.setMarketParameters(newMarketParameters);

        // get new params
        SwanMarketParameters memory _newMarketParameters = swan.getCurrentMarketParameters();
        assertEq(_newMarketParameters.listingInterval, newMarketParameters.listingInterval);
        assertEq(_newMarketParameters.buyInterval, newMarketParameters.buyInterval);
        assertEq(_newMarketParameters.withdrawInterval, newMarketParameters.withdrawInterval);
    }

    /// @dev Checks if the round, phase and timeRemaining is correct
    function checkRoundAndPhase(SwanAgent _agent, SwanAgent.Phase phase, uint256 round) public view returns (uint256) {
        // get the current round and phase of the agent
        (uint256 _currRound, SwanAgent.Phase _currPhase,) = _agent.getRoundPhase();
        assertEq(uint8(_currPhase), uint8(phase));
        assertEq(uint8(_currRound), uint8(round));

        // return the last timestamp to use in test
        return block.timestamp;
    }
}
