// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SwanAgent} from "./SwanAgent.sol";
import {LLMOracleCoordinator} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";
import {LLMOracleTaskParameters} from "@firstbatch/dria-oracle-contracts/LLMOracleTask.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Interface for JokeRace contest interactions
/// @dev Provides functions to interact with JokeRace contests and query their state
/// @notice Interface for JokeRace contest interactions
/// @dev Provides functions to interact with JokeRace contests and query their state
interface IJokeRaceContest {
    /// @notice Represents the current state of a contest
    /// @dev Used to control valid operations at different stages
    enum ContestState {
        NotStarted, // contest created/not started
        Active, // contest ongoing/accepting votes
        Canceled, // contest canceled before completion
        Queued, // contest queued for start
        Completed // contest ended/votes are final

    }

    /// @notice Returns current contest state
    /// @return Current state of the contest
    function state() external view returns (ContestState);

    /// @notice Returns vote counts for a proposal
    /// @param proposalId The ID of the proposal to query
    /// @return votes Number of votes
    function proposalVotes(uint256 proposalId) external view returns (uint256 votes);

    /// @notice Returns all proposal IDs in the contest
    /// @return Array of proposal IDs
    function getAllProposalIds() external view returns (uint256[] memory);

    /// @notice Returns proposal details
    /// @param proposalId The ID of the proposal to query
    /// @return author Address that created the proposal
    /// @return exists Whether the proposal exists
    /// @return description Text description of the proposal
    function proposals(uint256 proposalId)
        external
        view
        returns (address author, bool exists, string memory description);
}

/// @title SwanDebate
/// @notice Contract for managing AI agent debates on JokeRace contests
/// @dev Coordinates AI agent interactions and voting outcomes through LLMOracleCoordinator
contract SwanDebate is Ownable, Pausable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    /// @notice Thrown when attempting to interact with an inactive debate
    /// @param contest The ID of the debate that is not active
    error DebateNotActive(address contest);

    /// @notice Thrown when an invalid agent id is provided
    /// @param agentId The invalid agent id
    error InvalidAgent(uint256 agentId);

    /// @notice Thrown when attempting to create a debate for a contest that already has one
    /// @param contest The contest address that already has a debate
    error DebateAlreadyExists(address contest);

    /// @notice Thrown when contest is in wrong state for an operation
    /// @param currentState Current state of the contest
    /// @param expectedState Required state for the operation
    error ContestInvalidState(IJokeRaceContest.ContestState currentState, IJokeRaceContest.ContestState expectedState);

    /// @notice Thrown when attempting to record output for a non-existent task
    error TaskNotRequested();

    /// @notice Thrown when trying to use an unregistered agent
    error AgentNotRegistered();

    /// @notice Thrown when an invalid number of proposals exist in a debate
    error InvalidProposalCount(uint256 count);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Emitted when a new agent is registered
    /// @param agentId ID of the registered agent
    event AgentRegistered(uint256 indexed agentId);

    /// @notice Emitted when a new debate is initialized
    /// @param contest Address of the JokeRace contest
    /// @param agent1Id ID of first participating agent
    /// @param agent2Id ID of second participating agent
    event DebateInitialized(address indexed contest, uint256 indexed agent1Id, uint256 indexed agent2Id);

    /// @notice Emitted when an oracle output is recorded for an agent
    /// @param contest Address of the JokeRace contest
    /// @param round Current round number
    /// @param agentId ID of agent providing output
    /// @param taskId Oracle task identifier
    event OracleOutputRecorded(address indexed contest, uint256 indexed round, uint256 indexed agentId, uint256 taskId);

    /// @notice Emitted when a debate is concluded
    /// @param contest Address of the JokeRace contest
    /// @param winningAgentId ID of winning agent
    /// @param finalVotes Number of votes received by winner
    event DebateTerminated(address indexed contest, uint256 winningAgentId, uint256 finalVotes);

    /// @notice Emitted when a new oracle request is made
    /// @param contest Address of the JokeRace contest
    /// @param round Current round number
    /// @param agentId ID of agent making request
    /// @param taskId Oracle task identifier
    event OracleRequested(address indexed contest, uint256 indexed round, uint256 indexed agentId, uint256 taskId);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @notice Represents an AI agent in the debate system
    /// @dev Tracks registration status and win count
    struct Agent {
        bool isRegistered;
        uint256 wins;
    }

    /// @notice Represents a debate between two agents
    /// @dev Uses a mapping for rounds to allow unlimited round progression
    struct Debate {
        uint256 agent1Id;
        uint256 agent2Id;
        uint256 agent1ProposalId;
        uint256 agent2ProposalId;
        uint256 currentRound;
        uint256 winnerId;
        mapping(uint256 => RoundData) rounds;
    }

    /// @notice Contains data for a single debate round
    /// @dev Stores oracle outputs and completion status for both agents
    /// @dev Both agents must provide output before round is marked complete
    /// @dev Round completion increments currentRound in the parent Debate
    struct RoundData {
        bool roundComplete; // whether both agents have submitted outputs
        uint256 agent1TaskId; // oracle task id for agent1's response
        uint256 agent2TaskId; // oracle task id for agent2's response
        bytes agent1Output; // oracle output for agent1
        bytes agent2Output; // oracle output for agent2
    }

    /// @notice Oracle coordinator contract for AI responses
    LLMOracleCoordinator public immutable coordinator;

    /// @notice Protocol identifier for oracle requests
    /// @dev Used to identify requests from this contract in the oracle system
    bytes32 public constant DEBATE_PROTOCOL = "swan-debate/0.1.0";

    uint256 public nextAgentId = 1;

    /// @notice Mapping of agent IDs to their details
    mapping(uint256 => Agent) public agents;
    /// @notice Maps contest addresses to their debate data
    mapping(address contest => Debate) public debates;

    /// @notice Maps agent addresses to their participated contest addresses
    mapping(uint256 agentId => address[] contests) public agentDebates;

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS 
    //////////////////////////////////////////////////////////////*/
    /// @notice Ensures debate is active (has current round and no winner)
    /// @param contest Address of the debate contest
    modifier onlyActiveDebate(address contest) {
        Debate storage debate = debates[contest];
        if (debate.currentRound == 0 || debate.winnerId != 0) {
            revert DebateNotActive(contest);
        }
        _;
    }

    /// @notice Ensures contest is in expected state
    /// @param contest Address of the contest
    /// @param expectedState The state the contest should be in
    modifier onlyContestState(address contest, IJokeRaceContest.ContestState expectedState) {
        IJokeRaceContest jokeContest = IJokeRaceContest(contest);
        if (jokeContest.state() != expectedState) {
            revert ContestInvalidState(jokeContest.state(), expectedState);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /// @notice Initializes the SwanDebate contract
    /// @param _coordinator Address of the LLMOracleCoordinator contract
    /// @dev Sets the immutable coordinator reference and initializes ownership
    constructor(address _coordinator) Ownable(msg.sender) {
        coordinator = LLMOracleCoordinator(_coordinator);
    }

    /*//////////////////////////////////////////////////////////////
                              CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Register a new agent with their system prompt
    /// @return newAgentId The ID of the newly registered agent
    function registerAgent() external onlyOwner returns (uint256 newAgentId) {
        uint256 agentId = nextAgentId++;
        agents[agentId] = Agent({isRegistered: true, wins: 0});

        emit AgentRegistered(agentId);
        return agentId;
    }

    /// @notice Initialize a new debate between two agents
    /// @param _agent1Id ID of the first agent
    /// @param _agent2Id ID of the second agent
    /// @param _contest Address of the JokeRace contest
    /// @return contestAddress The address of the initialized contest
    /// @dev Verifies agent registration and contest state before initialization
    function initializeDebate(uint256 _agent1Id, uint256 _agent2Id, address _contest)
        external
        onlyOwner
        whenNotPaused
        returns (address contestAddress)
    {
        if (!agents[_agent1Id].isRegistered || !agents[_agent2Id].isRegistered) {
            revert AgentNotRegistered();
        }

        Debate storage debate = debates[_contest];
        if (debate.currentRound != 0) revert DebateAlreadyExists(_contest);

        IJokeRaceContest contest = IJokeRaceContest(_contest);

        uint256[] memory proposalIds = contest.getAllProposalIds();
        if (proposalIds.length != 2) {
            revert InvalidProposalCount(proposalIds.length);
        }

        debate.agent1Id = _agent1Id;
        debate.agent2Id = _agent2Id;
        debate.agent1ProposalId = proposalIds[0];
        debate.agent2ProposalId = proposalIds[1];
        debate.currentRound = 1;
        debate.winnerId = 0;

        agentDebates[_agent1Id].push(_contest);
        agentDebates[_agent2Id].push(_contest);

        emit DebateInitialized(_contest, _agent1Id, _agent2Id);

        return _contest;
    }

    /// @notice Request oracle output for an agent
    /// @param _contest Address of the contest for the debate
    /// @param _agentId ID of the agent making the request
    /// @param _input Input data for the oracle request
    /// @param _models Model parameters for the oracle
    /// @param _oracleParameters Oracle task configuration parameters
    /// @dev Only the owner can request outputs and the contest must be Active
    function requestOracleOutput(
        address _contest,
        uint256 _agentId,
        bytes calldata _input,
        bytes calldata _models,
        LLMOracleTaskParameters calldata _oracleParameters
    )
        external
        onlyOwner
        whenNotPaused
        onlyActiveDebate(_contest)
        onlyContestState(_contest, IJokeRaceContest.ContestState.Active)
        returns (uint256 taskId)
    {
        if (!agents[_agentId].isRegistered) revert AgentNotRegistered();

        Debate storage debate = debates[_contest];
        if (_agentId != debate.agent1Id && _agentId != debate.agent2Id) revert InvalidAgent(_agentId);

        taskId = coordinator.request(DEBATE_PROTOCOL, _input, _models, _oracleParameters);
        emit OracleRequested(_contest, debate.currentRound, _agentId, taskId);
    }

    /// @notice Records an oracle output for an agent in a debate round
    /// @param _contest Address of the JokeRace contest
    /// @param _agentId ID of the agent providing output
    /// @param _taskId ID of the oracle task
    /// @dev Only owner can record outputs and both agents must provide output to complete a round
    function recordOracleOutput(address _contest, uint256 _agentId, uint256 _taskId)
        external
        onlyOwner
        whenNotPaused
        onlyActiveDebate(_contest)
        onlyContestState(_contest, IJokeRaceContest.ContestState.Active)
    {
        if (!agents[_agentId].isRegistered) revert AgentNotRegistered();

        Debate storage debate = debates[_contest];

        if (_taskId == 0) revert TaskNotRequested();

        RoundData storage round = debate.rounds[debate.currentRound];
        if (_agentId == debate.agent1Id) {
            round.agent1TaskId = _taskId;
            round.agent1Output = coordinator.getBestResponse(_taskId).output;
        } else if (_agentId == debate.agent2Id) {
            round.agent2TaskId = _taskId;
            round.agent2Output = coordinator.getBestResponse(_taskId).output;
        } else {
            revert InvalidAgent(_agentId);
        }

        if (round.agent1Output.length > 0 && round.agent2Output.length > 0) {
            round.roundComplete = true;
            debate.currentRound++;
        }

        emit OracleOutputRecorded(_contest, debate.currentRound, _agentId, _taskId);
    }

    /// @notice Terminates a debate and retrieves the winner from JokeRace contest
    /// @dev Requires contest state to be `Completed`, sorts proposals, and fetches the winner
    /// @param _contest Address of the JokeRace contest
    function terminateDebate(address _contest) external onlyOwner whenNotPaused {
        Debate storage debate = debates[_contest];
        IJokeRaceContest contest = IJokeRaceContest(_contest);

        uint256 agent1ProposalVotes = contest.proposalVotes(debate.agent1ProposalId);
        uint256 agent2ProposalVotes = contest.proposalVotes(debate.agent2ProposalId);

        uint256 winnerId;
        if (agent1ProposalVotes >= agent2ProposalVotes) {
            winnerId = debate.agent1Id;
        } else {
            winnerId = debate.agent2Id;
        }

        debate.winnerId = winnerId;
        agents[winnerId].wins += 1;

        emit DebateTerminated(
            _contest, winnerId, agent1ProposalVotes >= agent2ProposalVotes ? agent1ProposalVotes : agent2ProposalVotes
        );
    }

    /*//////////////////////////////////////////////////////////////
                           PAUSE FUNCTIONALITY
    //////////////////////////////////////////////////////////////*/

    /// @notice Pauses all debate operations
    /// @dev Only owner can pause, prevents new debates and updates to existing ones
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses all debate operations
    /// @dev Only owner can unpause, allows debate operations to resume
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Get an agent's information by their ID
    /// @param _agentId The ID of the agent to query
    /// @return agentInfo The Agent struct containing the agent's information
    function getAgent(uint256 _agentId) external view returns (Agent memory agentInfo) {
        return agents[_agentId];
    }

    /// @notice Retrieves round data for a specific debate round
    /// @param _contest Address of the JokeRace contest
    /// @param _round Round number to query
    /// @return roundData RoundData structure containing the round's information
    function getRoundForDebate(address _contest, uint256 _round) external view returns (RoundData memory roundData) {
        return debates[_contest].rounds[_round];
    }

    /// @notice Gets the latest round data for a debate
    /// @param _contest Address of the JokeRace contest
    /// @return latestRound RoundData structure containing the current round's information
    function getLatestRoundForDebate(address _contest) external view returns (RoundData memory latestRound) {
        return debates[_contest].rounds[debates[_contest].currentRound];
    }

    /// @notice Retrieves basic information about a debate
    /// @param _contest Address of the JokeRace contest
    /// @return agent1Id ID of first participating agent
    /// @return agent2Id ID of second participating agent
    /// @return currentRound Current round number
    /// @return winnerId ID of winning agent (0 means no winner yet)
    function getDebateInfo(address _contest)
        external
        view
        returns (uint256 agent1Id, uint256 agent2Id, uint256 currentRound, uint256 winnerId)
    {
        Debate storage debate = debates[_contest];
        return (debate.agent1Id, debate.agent2Id, debate.currentRound, debate.winnerId);
    }

    /// @notice Gets all debates an agent has participated in
    /// @param _agentId ID of the agent
    /// @return agentContests Array of contest addresses the agent participated in
    function getAgentDebates(uint256 _agentId) external view returns (address[] memory agentContests) {
        return agentDebates[_agentId];
    }

    /// @notice Approves a spender to spend a certain amount of the specified fee token
    /// @dev Only the contract owner can call this function
    /// @param feeToken The address of the ERC20 token to approve
    /// @param spender The address allowed to spend the tokens
    /// @param amount The amount of tokens to approve for the spender
    function approveFeeToken(address feeToken, address spender, uint256 amount) external onlyOwner {
        IERC20(feeToken).approve(spender, amount);
    }
}
