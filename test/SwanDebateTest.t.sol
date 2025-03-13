// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Helper} from "./Helper.t.sol";
import {SwanDebate} from "../src/SwanDebate.sol";
import {LLMOracleCoordinator} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";
import {SwanAgent} from "../src/SwanAgent.sol";
import {IJokeRaceContest} from "../src/SwanDebate.sol";
import {LLMOracleTaskParameters} from "@firstbatch/dria-oracle-contracts/LLMOracleTask.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/Test.sol";
import {MockJokeRaceContest} from "./mock/MockJokeRaceContest.sol";
import {MockOracle} from "./mock/MockOracle.sol";

contract SwanDebateTest is Helper {
    SwanDebate public debate;
    MockJokeRaceContest public jokeRace;
    LLMOracleCoordinator public coordinator;
    bytes public constant TEST_OUTPUT = "test output";

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

    function setUp() public override {
        super.setUp();
        jokeRace = new MockJokeRaceContest();
        coordinator = oracleCoordinator;
        debate = new SwanDebate(address(coordinator));

        // Fund debate contract with WETH
        deal(address(token), address(debate), 100 ether);

        // Approve coordinator
        vm.prank(address(debate));
        token.approve(address(coordinator), type(uint256).max);
    }

    function setupDebate() internal returns (address contestAddr, uint256 agent1Id, uint256 agent2Id) {
        agent1Id = debate.registerAgent();
        agent2Id = debate.registerAgent();

        // Set up two proposals in JokeRace
        jokeRace.setProposalAuthor(1, address(this));
        jokeRace.setProposalAuthor(2, address(this));

        jokeRace.setState(IJokeRaceContest.ContestState.Queued);
        contestAddr = address(jokeRace);
        debate.initializeDebate(agent1Id, agent2Id, contestAddr);
    }

    function setupOracleOutput(
        address contest,
        uint256 agentId,
        bytes memory _input,
        bytes memory _models,
        LLMOracleTaskParameters memory params
    ) internal returns (uint256 taskId) {
        jokeRace.setState(IJokeRaceContest.ContestState.Active);

        taskId = debate.requestOracleOutput(contest, agentId, _input, _models, params);

        (address requester,,,,,,, bytes memory taskInput,) = coordinator.requests(taskId);

        // Handle first generator (state: Open -> Processing)
        {
            vm.startPrank(generators[0]);
            bytes memory message = abi.encodePacked(taskId, taskInput, requester, generators[0], uint256(0));

            uint256 nonce;
            uint256 target = type(uint256).max >> params.difficulty;
            while (uint256(keccak256(message)) >= target) {
                nonce++;
                message = abi.encodePacked(taskId, taskInput, requester, generators[0], nonce);
            }
            coordinator.respond(taskId, nonce, TEST_OUTPUT, "0x");
            vm.stopPrank();
        }

        vm.warp(block.timestamp + 1);

        // Handle second generator (state: Processing -> Validating)
        {
            vm.startPrank(generators[1]);
            bytes memory message = abi.encodePacked(taskId, taskInput, requester, generators[1], uint256(0));

            uint256 nonce;
            uint256 target = type(uint256).max >> params.difficulty;
            while (uint256(keccak256(message)) >= target) {
                nonce++;
                message = abi.encodePacked(taskId, taskInput, requester, generators[1], nonce);
            }
            coordinator.respond(taskId, nonce, TEST_OUTPUT, "0x");
            vm.stopPrank();
        }

        vm.warp(block.timestamp + 1);

        // Handle validator (state: Validating -> Completed)
        {
            vm.startPrank(validators[0]);
            bytes memory message = abi.encodePacked(taskId, taskInput, requester, validators[0], uint256(0));

            uint256 nonce;
            uint256 target = type(uint256).max >> params.difficulty;
            while (uint256(keccak256(message)) >= target) {
                nonce++;
                message = abi.encodePacked(taskId, taskInput, requester, validators[0], nonce);
            }
            coordinator.validate(taskId, nonce, scores, "0x");
            vm.stopPrank();
        }

        vm.warp(block.timestamp + 1);

        debate.recordOracleOutput(contest, agentId, taskId);
    }

    function test_CompleteDebateFlow() external fund addValidatorsToWhitelist registerOracles {
        (address contestAddr, uint256 agent1Id, uint256 agent2Id) = setupDebate();

        jokeRace.setState(IJokeRaceContest.ContestState.Active);

        bytes memory input = bytes("Test input");
        bytes memory models = bytes("gpt-4");

        // First agent
        setupOracleOutput(contestAddr, agent1Id, input, models, oracleParameters);
        vm.warp(block.timestamp + 1);

        // Second agent
        setupOracleOutput(contestAddr, agent2Id, input, models, oracleParameters);
        vm.warp(block.timestamp + 1);

        SwanDebate.RoundData memory roundData = debate.getRoundForDebate(contestAddr, 1);
        assertTrue(roundData.roundComplete, "Round should be complete");

        // Assign votes correctly
        jokeRace.setProposalVotes(1, 100);
        jokeRace.setProposalVotes(2, 50);

        jokeRace.setState(IJokeRaceContest.ContestState.Completed);

        // Ensure sorted proposals are set before determining the winner
        jokeRace.setSortedAndTiedProposals();

        // Terminate debate and determine winner
        debate.terminateDebate(contestAddr);

        // Fetch sorted proposals to get the actual winner
        uint256[] memory sortedProposals = jokeRace.sortedProposalIds();
        uint256 winningProposal = sortedProposals[sortedProposals.length - 1];

        uint256[] memory proposalIds = jokeRace.getAllProposalIds();
        uint256 expectedWinner = (proposalIds[0] == winningProposal) ? agent1Id : agent2Id;

        (,,, uint256 winnerId) = debate.getDebateInfo(contestAddr);
        assertEq(winnerId, expectedWinner, "Winner should be correctly determined from sorted proposals");
    }

    function test_ConcurrentDebates() external {
        address[] memory contests = new address[](3);
        uint256 agent1Id = debate.registerAgent();
        uint256 agent2Id = debate.registerAgent();

        for (uint256 i = 0; i < 3; i++) {
            MockJokeRaceContest newContest = new MockJokeRaceContest();
            // Set up proposals
            newContest.setProposalAuthor(1, address(this));
            newContest.setProposalAuthor(2, address(this));
            newContest.setState(IJokeRaceContest.ContestState.Queued);
            contests[i] = address(newContest);

            debate.initializeDebate(agent1Id, agent2Id, address(newContest));
        }

        address[] memory agent1Debates = debate.getAgentDebates(agent1Id);
        assertEq(agent1Debates.length, 3, "Should track all debates");
    }

    function test_RevertScenarios() external {
        // Test multiple revert cases
        vm.expectRevert(abi.encodeWithSelector(SwanDebate.AgentNotRegistered.selector));
        debate.initializeDebate(0, 2, address(jokeRace));

        uint256 agent1Id = debate.registerAgent();
        uint256 agent2Id = debate.registerAgent();

        // Wrong contest state
        jokeRace.setState(IJokeRaceContest.ContestState.Active);
        vm.expectRevert(
            abi.encodeWithSelector(
                SwanDebate.ContestInvalidState.selector,
                IJokeRaceContest.ContestState.Active,
                IJokeRaceContest.ContestState.Queued
            )
        );
        debate.initializeDebate(agent1Id, agent2Id, address(jokeRace));
    }

    function test_ViewFunctions() external {
        (address contestAddr, uint256 agent1Id,) = setupDebate();

        // Test getAgent
        SwanDebate.Agent memory agent = debate.getAgent(agent1Id);
        assertTrue(agent.isRegistered, "Agent should be registered");

        // Test getRoundForDebate
        SwanDebate.RoundData memory roundData = debate.getRoundForDebate(contestAddr, 1);
        assertEq(roundData.roundComplete, false, "New round should not be complete");

        // Test getLatestRoundForDebate
        SwanDebate.RoundData memory latestRound = debate.getLatestRoundForDebate(contestAddr);
        assertEq(latestRound.roundComplete, false, "Latest round should not be complete");
    }

    function test_InvalidOracleRequest() external fund addValidatorsToWhitelist registerOracles {
        (address contestAddr,,) = setupDebate();
        jokeRace.setState(IJokeRaceContest.ContestState.Active);

        // Test with invalid agent ID
        uint256 invalidAgentId = 999;
        bytes memory input = bytes("Test input");
        bytes memory models = bytes("gpt-4");

        vm.expectRevert(abi.encodeWithSelector(SwanDebate.AgentNotRegistered.selector)); // Changed error
        debate.requestOracleOutput(contestAddr, invalidAgentId, input, models, oracleParameters);
    }

    function test_MultipleRounds() external fund addValidatorsToWhitelist registerOracles {
        (address contestAddr, uint256 agent1Id, uint256 agent2Id) = setupDebate();

        // Complete first round
        bytes memory input = bytes("Test input");
        bytes memory models = bytes("gpt-4");

        setupOracleOutput(contestAddr, agent1Id, input, models, oracleParameters);
        setupOracleOutput(contestAddr, agent2Id, input, models, oracleParameters);

        // Verify round completion
        SwanDebate.RoundData memory round1Data = debate.getRoundForDebate(contestAddr, 1);
        assertTrue(round1Data.roundComplete, "First round should be complete");

        // Start second round
        setupOracleOutput(contestAddr, agent1Id, input, models, oracleParameters);
        setupOracleOutput(contestAddr, agent2Id, input, models, oracleParameters);

        // Verify second round completion
        SwanDebate.RoundData memory round2Data = debate.getRoundForDebate(contestAddr, 2);
        assertTrue(round2Data.roundComplete, "Second round should be complete");
    }

    function test_EdgeCase_UnregisteredAgent() public {
        (, uint256 validAgentId,) = setupDebate();

        uint256 invalidAgentId = 999;
        MockJokeRaceContest newContest = new MockJokeRaceContest();
        newContest.setProposalAuthor(1, address(this));
        newContest.setProposalAuthor(2, address(this));
        newContest.setState(IJokeRaceContest.ContestState.Queued);

        vm.expectRevert(SwanDebate.AgentNotRegistered.selector);
        debate.initializeDebate(invalidAgentId, validAgentId, address(newContest));
    }

    function test_EdgeCase_InvalidContestState() public {
        (, uint256 agent1Id, uint256 agent2Id) = setupDebate();

        MockJokeRaceContest newContest = new MockJokeRaceContest();
        newContest.setState(IJokeRaceContest.ContestState.Active);
        newContest.setProposalAuthor(1, address(this));
        newContest.setProposalAuthor(2, address(this));

        vm.expectRevert(
            abi.encodeWithSelector(
                SwanDebate.ContestInvalidState.selector,
                IJokeRaceContest.ContestState.Active,
                IJokeRaceContest.ContestState.Queued
            )
        );
        debate.initializeDebate(agent1Id, agent2Id, address(newContest));
    }

    function test_EdgeCase_DuplicateDebate() public {
        (address contestAddr, uint256 agent1Id, uint256 agent2Id) = setupDebate();

        vm.expectRevert(abi.encodeWithSelector(SwanDebate.DebateAlreadyExists.selector, contestAddr));
        debate.initializeDebate(agent1Id, agent2Id, contestAddr);
    }
}
