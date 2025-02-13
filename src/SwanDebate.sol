// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SwanAgent} from "./SwanAgent.sol";
import {LLMOracleCoordinator} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";
import {LLMOracleTaskParameters} from "@firstbatch/dria-oracle-contracts/LLMOracleTask.sol";

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
    /// @return forVotes Number of votes in favor
    /// @return againstVotes Number of votes against
    function proposalVotes(uint256 proposalId) external view returns (uint256 forVotes, uint256 againstVotes);

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

contract SwanDebate is Ownable, Pausable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when attempting to interact with an inactive debate
    /// @param debateId The ID of the debate that is not active
    error DebateNotActive(uint256 debateId);

    /// @notice Thrown when an invalid agent address is provided
    /// @param agent The invalid agent address
    error InvalidAgent(address agent);

    /// @notice Thrown when attempting to create a debate for a contest that already has one
    /// @param contest The contest address that already has a debate
    error DebateAlreadyExists(address contest);

    /// @notice Thrown when contest is in wrong state for an operation
    /// @param have Current state of the contest
    /// @param want Required state for the operation
    error ContestInvalidState(IJokeRaceContest.ContestState have, IJokeRaceContest.ContestState want);

    /// @notice Thrown when attempting to record output for a non-existent task
    error TaskNotRequested();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new debate is initialized
    /// @param debateId Unique identifier for the debate (contest address as uint)
    /// @param agent1 Address of first participating agent
    /// @param agent2 Address of second participating agent
    /// @param jokeRaceContest Address of associated JokeRace contest
    event DebateInitialized(
        uint256 indexed debateId, address indexed agent1, address indexed agent2, address jokeRaceContest
    );

    /// @notice Emitted when an oracle output is recorded for an agent
    /// @param debateId Identifier of the debate
    /// @param round Current round number
    /// @param agent Address of agent providing output
    /// @param taskId Oracle task identifier
    /// @param output Raw output data from oracle
    event OracleOutputRecorded(
        uint256 indexed debateId, uint256 indexed round, address indexed agent, uint256 taskId, bytes output
    );

    /// @notice Emitted when a debate is concluded
    /// @param debateId Identifier of the debate
    /// @param winner Address of winning agent
    /// @param finalVotes Number of votes received by winner
    event DebateTerminated(uint256 indexed debateId, address winner, uint256 finalVotes);

    /// @notice Emitted when a new oracle request is made
    /// @param debateId Identifier of the debate
    /// @param round Current round number
    /// @param agent Address of agent making request
    /// @param taskId Oracle task identifier
    event OracleRequested(uint256 indexed debateId, uint256 indexed round, address indexed agent, uint256 taskId);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Represents a debate between two agents
    /// @dev Uses a mapping for rounds to allow unlimited round progression
    struct Debate {
        address agent1; // first participating agent
        address agent2; // second participating agent
        uint256 currentRound; // current round number (0 means not active/terminated)
        address winner; // winner address (address(0) means no winner yet)
        mapping(uint256 => RoundData) rounds; // round number to round data mapping
    }

    /// @notice Contains data for a single debate round
    /// @dev Stores oracle outputs and completion status for both agents
    struct RoundData {
        uint256 agent1TaskId; // oracle task id for agent1's response
        uint256 agent2TaskId; // oracle task id for agent2's response
        bytes agent1Output; // oracle output for agent1
        bytes agent2Output; // oracle output for agent2
        bool roundComplete; // whether both agents have submitted outputs
    }

    /// @notice Oracle coordinator contract for AI responses
    LLMOracleCoordinator public immutable coordinator;

    /// @notice Protocol identifier for oracle requests
    bytes32 public constant DEBATE_PROTOCOL = "swan-debate/0.1.0";

    /// @notice Maps contest addresses to their debate data
    mapping(address contest => Debate) public debates;

    /// @notice Maps agent addresses to their participated contest addresses
    mapping(address agent => address[] contests) public agentDebates;

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

    /// @notice Initializes a new debate between two agents based on a JokeRace contest
    /// @param _agent1 Address of the first agent participant
    /// @param _agent2 Address of the second agent participant
    /// @param _jokeRaceContest Address of the JokeRace contest to use for voting
    /// @return Address of the initialized contest
    /// @dev Only the owner can initialize debates and the contest must be in Queued state
    function initializeDebate(address _agent1, address _agent2, address _jokeRaceContest)
        external
        onlyOwner
        whenNotPaused
        returns (address)
    {
        // Validate agent addresses are not zero
        if (_agent1 == address(0) || _agent2 == address(0)) revert InvalidAgent(address(0));

        // Check if debate already exists for this contest
        Debate storage debate = debates[_jokeRaceContest];
        if (debate.currentRound != 0) revert DebateAlreadyExists(_jokeRaceContest);

        // Verify contest is in correct state for initialization
        IJokeRaceContest contest = IJokeRaceContest(_jokeRaceContest);
        if (contest.state() != IJokeRaceContest.ContestState.Queued) {
            revert ContestInvalidState(contest.state(), IJokeRaceContest.ContestState.Queued);
        }

        // Set initial debate parameters
        debate.agent1 = _agent1;
        debate.agent2 = _agent2;
        debate.currentRound = 1;
        debate.winner = address(0);

        // Track debate participation for each agent
        agentDebates[_agent1].push(_jokeRaceContest);
        agentDebates[_agent2].push(_jokeRaceContest);

        emit DebateInitialized(uint256(uint160(_jokeRaceContest)), _agent1, _agent2, _jokeRaceContest);
        return _jokeRaceContest;
    }

    /// @param _agent Address of the agent making the request
    /// @param _input Input data for the oracle request
    /// @param _models Model parameters for the oracle
    /// @param _oracleParameters Oracle task configuration parameters
    /// @return taskId The ID of the created oracle task
    /// @dev Only the owner can request outputs and the contest must be Active
    function requestOracleOutput(
        address _contest,
        address _agent,
        bytes calldata _input,
        bytes calldata _models,
        LLMOracleTaskParameters calldata _oracleParameters
    ) external onlyOwner whenNotPaused returns (uint256 taskId) {
        // Verify debate is active and no winner determined
        Debate storage debate = debates[_contest];
        if (debate.currentRound == 0 || debate.winner != address(0)) revert DebateNotActive(0);

        // Ensure agent is a participant
        if (_agent != debate.agent1 && _agent != debate.agent2) revert InvalidAgent(_agent);

        // Check contest is in active state
        IJokeRaceContest contest = IJokeRaceContest(_contest);
        if (contest.state() != IJokeRaceContest.ContestState.Active) {
            revert ContestInvalidState(contest.state(), IJokeRaceContest.ContestState.Active);
        }

        // Handle token approvals and make oracle request
        SwanAgent agent = SwanAgent(_agent);
        (uint256 totalFee,,) = coordinator.getFee(_oracleParameters);
        agent.swan().token().approve(address(coordinator), totalFee);
        taskId = coordinator.request(DEBATE_PROTOCOL, _input, _models, _oracleParameters);

        emit OracleRequested(uint256(uint160(_contest)), debate.currentRound, _agent, taskId);
    }

    /// @notice Records an oracle output for an agent in a debate round
    /// @param _contest Address of the JokeRace contest
    /// @param _agent Address of the agent providing output
    /// @param _taskId ID of the oracle task
    /// @param _output Output data from the oracle
    /// @dev Only owner can record outputs and both agents must provide output to complete a round
    function recordOracleOutput(address _contest, address _agent, uint256 _taskId, bytes calldata _output)
        external
        onlyOwner
        whenNotPaused
    {
        // verify debate is active and no winner determined
        Debate storage debate = debates[_contest];
        if (debate.currentRound == 0 || debate.winner != address(0)) revert DebateNotActive(0);

        // check contest is in active state
        IJokeRaceContest contest = IJokeRaceContest(_contest);
        if (contest.state() != IJokeRaceContest.ContestState.Active) {
            revert ContestInvalidState(contest.state(), IJokeRaceContest.ContestState.Active);
        }

        // ensure task id is valid
        if (_taskId == 0) revert TaskNotRequested();

        // store output for corresponding agent
        RoundData storage round = debate.rounds[debate.currentRound];
        if (_agent == debate.agent1) {
            round.agent1TaskId = _taskId;
            round.agent1Output = _output;
        } else if (_agent == debate.agent2) {
            round.agent2TaskId = _taskId;
            round.agent2Output = _output;
        } else {
            revert InvalidAgent(_agent);
        }

        // advance round if both agents have submitted outputs
        if (round.agent1Output.length > 0 && round.agent2Output.length > 0) {
            round.roundComplete = true;
            debate.currentRound++;
        }

        emit OracleOutputRecorded(0, debate.currentRound, _agent, _taskId, _output);
    }

    /// @notice Terminates a debate and determines the winner based on JokeRace voting
    /// @param _contest Address of the JokeRace contest
    /// @dev Only owner can terminate and contest must be in Completed state
    function terminateDebate(address _contest) external onlyOwner whenNotPaused {
        // verify debate is active and no winner determined
        Debate storage debate = debates[_contest];
        if (debate.currentRound == 0 || debate.winner != address(0)) revert DebateNotActive(0);

        // check contest is completed
        IJokeRaceContest contest = IJokeRaceContest(_contest);
        if (contest.state() != IJokeRaceContest.ContestState.Completed) {
            revert ContestInvalidState(contest.state(), IJokeRaceContest.ContestState.Completed);
        }

        // determine winner from proposal votes
        uint256[] memory proposalIds = contest.getAllProposalIds();
        (address winner, uint256 winningVotes) = _determineWinner(contest, proposalIds, debate.agent1, debate.agent2);

        if (winner == address(0)) revert InvalidAgent(address(0));

        // update debate state and emit result
        debate.winner = winner;
        debate.currentRound = 0; // mark as terminated
        emit DebateTerminated(0, winner, winningVotes);
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

    /// @notice Retrieves round data for a specific debate round
    /// @param _contest Address of the JokeRace contest
    /// @param _round Round number to query
    /// @return RoundData structure containing the round's information
    function getRoundForDebate(address _contest, uint256 _round) external view returns (RoundData memory) {
        return debates[_contest].rounds[_round];
    }

    /// @notice Gets the latest round data for a debate
    /// @param _contest Address of the JokeRace contest
    /// @return RoundData structure containing the current round's information
    function getLatestRoundForDebate(address _contest) external view returns (RoundData memory) {
        return debates[_contest].rounds[debates[_contest].currentRound];
    }

    /// @notice Retrieves basic information about a debate
    /// @param _contest Address of the JokeRace contest
    /// @return agent1 Address of first agent
    /// @return agent2 Address of second agent
    /// @return currentRound Current round number
    /// @return winner Address of winner (if determined)
    function getDebateInfo(address _contest)
        external
        view
        returns (address agent1, address agent2, uint256 currentRound, address winner)
    {
        Debate storage debate = debates[_contest];
        return (debate.agent1, debate.agent2, debate.currentRound, debate.winner);
    }

    /// @notice Gets all debates an agent has participated in
    /// @param agent Address of the agent
    /// @return Array of contest addresses the agent participated in
    function getAgentDebates(address agent) external view returns (address[] memory) {
        return agentDebates[agent];
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Determines the winner of a debate based on JokeRace voting results
    /// @param _contest JokeRace contest interface
    /// @param _proposalIds Array of proposal IDs to check
    /// @param _agent1 Address of first agent
    /// @param _agent2 Address of second agent
    /// @return winner Address of winning agent
    /// @return highestVotes Number of votes received by winner
    function _determineWinner(
        IJokeRaceContest _contest,
        uint256[] memory _proposalIds,
        address _agent1,
        address _agent2
    ) internal view returns (address winner, uint256 highestVotes) {
        // iterate through all proposals to find highest vote count
        for (uint256 i = 0; i < _proposalIds.length; i++) {
            (uint256 forVotes,) = _contest.proposalVotes(_proposalIds[i]);
            if (forVotes > highestVotes) {
                // check if proposal author is one of our agents
                (address author,,) = _contest.proposals(_proposalIds[i]);
                if (author == _agent1 || author == _agent2) {
                    highestVotes = forVotes;
                    winner = author;
                }
            }
        }
    }
}
