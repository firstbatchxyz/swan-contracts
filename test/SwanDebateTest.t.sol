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

/// @dev Mock implementation of `IJokeRaceContest`
contract MockJokeRaceContest is IJokeRaceContest {
    ContestState private _currentState;
    mapping(uint256 => uint256) private _votes;
    mapping(uint256 => address) private _authors;
    uint256[] private _proposalIds;

    function setState(ContestState _state) external {
        _currentState = _state;
    }

    function state() external view override returns (ContestState) {
        return _currentState;
    }

    function setProposalVotes(uint256 proposalId, uint256 votes) external {
        _votes[proposalId] = votes;
        if (!_proposalExists(proposalId)) {
            _proposalIds.push(proposalId);
        }
    }

    function setProposalAuthor(uint256 proposalId, address author) external {
        _authors[proposalId] = author;
        if (!_proposalExists(proposalId)) {
            _proposalIds.push(proposalId);
        }
    }

    function proposalVotes(uint256 proposalId)
        external
        view
        override
        returns (uint256 forVotes, uint256 againstVotes)
    {
        return (_votes[proposalId], 0);
    }

    function getAllProposalIds() external view override returns (uint256[] memory) {
        return _proposalIds;
    }

    function proposals(uint256 proposalId)
        external
        view
        override
        returns (address author, bool exists, string memory description)
    {
        return (_authors[proposalId], _proposalExists(proposalId), "Mock Proposal");
    }

    function _proposalExists(uint256 proposalId) internal view returns (bool) {
        for (uint256 i = 0; i < _proposalIds.length; i++) {
            if (_proposalIds[i] == proposalId) {
                return true;
            }
        }
        return false;
    }
}

/// @dev Mock Oracle Contract
contract MockOracle {
    mapping(uint256 => bytes) public responses;

    function getBestResponse(uint256 taskId) external view returns (bytes memory) {
        return responses[taskId];
    }

    function setResponse(uint256 taskId, bytes memory output) external {
        responses[taskId] = output;
    }
}

contract SwanDebateTest is Test {
    SwanDebate public debate;
    MockJokeRaceContest public jokeRace;
    MockOracle public oracle;
    LLMOracleCoordinator public coordinator;

    address public owner;

    event DebateInitialized(address indexed contest, uint256 indexed agent1Id, uint256 indexed agent2Id);
    event OracleOutputRecorded(
        address indexed contest, uint256 indexed round, uint256 indexed agentId, uint256 taskId, bytes output
    );
    event DebateTerminated(address indexed contest, uint256 winnerId, uint256 finalVotes);

    function setUp() public {
        owner = address(this);

        oracle = new MockOracle();
        jokeRace = new MockJokeRaceContest();
        coordinator = new LLMOracleCoordinator();

        debate = new SwanDebate(address(coordinator));
    }
}

contract SwanDebateIntegrationTest is Helper {
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

        debate.recordOracleOutput(contest, agentId, taskId, TEST_OUTPUT);
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

        jokeRace.setProposalVotes(1, 100);
        jokeRace.setProposalVotes(2, 50);

        jokeRace.setState(IJokeRaceContest.ContestState.Completed);
        debate.terminateDebate(contestAddr);

        (,,, uint256 winnerId) = debate.getDebateInfo(contestAddr);
        assertEq(winnerId, agent1Id, "Winner should be agent1");
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

    function test_Events() external {
        // Setup
        vm.recordLogs();

        // Action
        (address contestAddr, uint256 agent1Id, uint256 agent2Id) = setupDebate();

        // Get logs
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log memory lastEvent = entries[entries.length - 1];

        // Verify event
        bytes32 eventSig = lastEvent.topics[0];
        assertEq(keccak256("DebateInitialized(address,uint256,uint256)"), eventSig);

        address contestFromLog = address(uint160(uint256(lastEvent.topics[1])));
        uint256 agent1IdFromLog = uint256(lastEvent.topics[2]);
        uint256 agent2IdFromLog = uint256(lastEvent.topics[3]);

        assertEq(contestAddr, contestFromLog);
        assertEq(agent1Id, agent1IdFromLog);
        assertEq(agent2Id, agent2IdFromLog);
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

    function test_EdgeCases() external fund addValidatorsToWhitelist registerOracles {
        (address contestAddr, uint256 agent1Id,) = setupDebate();

        // Test terminating non-active debate
        address invalidContest = address(0x123);
        vm.expectRevert(abi.encodeWithSelector(SwanDebate.DebateNotActive.selector, invalidContest)); // Changed error
        debate.terminateDebate(invalidContest);

        // Test with non-existent task
        jokeRace.setState(IJokeRaceContest.ContestState.Active);
        vm.expectRevert(abi.encodeWithSelector(SwanDebate.TaskNotRequested.selector));
        debate.recordOracleOutput(contestAddr, agent1Id, 0, "");
    }
}
