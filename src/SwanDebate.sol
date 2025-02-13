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
    enum ContestState {
        NotStarted,
        Active,
        Canceled,
        Queued,
        Completed
    }

    /// @notice Returns current contest state
    function state() external view returns (ContestState);
    /// @notice Returns vote counts for a proposal
    function proposalVotes(uint256 proposalId) external view returns (uint256 forVotes, uint256 againstVotes);
    /// @notice Returns all proposal IDs in the contest
    function getAllProposalIds() external view returns (uint256[] memory);
    /// @notice Returns proposal details
    function proposals(uint256 proposalId)
        external
        view
        returns (address author, bool exists, string memory description);
}

contract SwanDebate is Ownable, Pausable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error DebateNotActive(uint256 debateId);
    error InvalidAgent(address agent);
    error DebateAlreadyExists(address contest);
    error ContestInvalidState(IJokeRaceContest.ContestState have, IJokeRaceContest.ContestState want);
    error TaskNotRequested();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event DebateInitialized(
        uint256 indexed debateId, address indexed agent1, address indexed agent2, address jokeRaceContest
    );
    event OracleOutputRecorded(
        uint256 indexed debateId, uint256 indexed round, address indexed agent, uint256 taskId, bytes output
    );
    event DebateTerminated(uint256 indexed debateId, address winner, uint256 finalVotes);
    event OracleRequested(uint256 indexed debateId, uint256 indexed round, address indexed agent, uint256 taskId);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    struct Debate {
        address agent1;
        address agent2;
        uint256 currentRound; // 0 means not active/terminated
        address winner; // address(0) means no winner yet
        mapping(uint256 => RoundData) rounds;
    }

    struct RoundData {
        uint256 agent1TaskId;
        uint256 agent2TaskId;
        bytes agent1Output;
        bytes agent2Output;
        bool roundComplete;
    }

    LLMOracleCoordinator public immutable coordinator;
    bytes32 public constant DEBATE_PROTOCOL = "swan-debate/0.1.0";

    mapping(address contest => Debate) public debates;
    mapping(address agent => address[] contests) public agentDebates;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _coordinator) Ownable(msg.sender) {
        coordinator = LLMOracleCoordinator(_coordinator);
    }

    /*//////////////////////////////////////////////////////////////
                              CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function initializeDebate(address _agent1, address _agent2, address _jokeRaceContest)
        external
        onlyOwner
        whenNotPaused
        returns (address)
    {
        if (_agent1 == address(0) || _agent2 == address(0)) revert InvalidAgent(address(0));

        Debate storage debate = debates[_jokeRaceContest];
        if (debate.currentRound != 0) revert DebateAlreadyExists(_jokeRaceContest);

        IJokeRaceContest contest = IJokeRaceContest(_jokeRaceContest);
        if (contest.state() != IJokeRaceContest.ContestState.Queued) {
            revert ContestInvalidState(contest.state(), IJokeRaceContest.ContestState.Queued);
        }

        debate.agent1 = _agent1;
        debate.agent2 = _agent2;
        debate.currentRound = 1;
        debate.winner = address(0);

        // Track agent debates
        agentDebates[_agent1].push(_jokeRaceContest);
        agentDebates[_agent2].push(_jokeRaceContest);

        emit DebateInitialized(uint256(uint160(_jokeRaceContest)), _agent1, _agent2, _jokeRaceContest);
        return _jokeRaceContest;
    }

    function requestOracleOutput(
        address _contest,
        address _agent,
        bytes calldata _input,
        bytes calldata _models,
        LLMOracleTaskParameters calldata _oracleParameters
    ) external onlyOwner whenNotPaused returns (uint256 taskId) {
        Debate storage debate = debates[_contest];
        if (debate.currentRound == 0 || debate.winner != address(0)) revert DebateNotActive(0);

        if (_agent != debate.agent1 && _agent != debate.agent2) revert InvalidAgent(_agent);

        IJokeRaceContest contest = IJokeRaceContest(_contest);
        if (contest.state() != IJokeRaceContest.ContestState.Active) {
            revert ContestInvalidState(contest.state(), IJokeRaceContest.ContestState.Active);
        }

        // Handle oracle fee approval using Swan's token
        SwanAgent agent = SwanAgent(_agent);
        (uint256 totalFee,,) = coordinator.getFee(_oracleParameters);

        // Get token through Swan instance
        agent.swan().token().approve(address(coordinator), totalFee);

        // Make oracle request
        taskId = coordinator.request(DEBATE_PROTOCOL, _input, _models, _oracleParameters);

        emit OracleRequested(uint256(uint160(_contest)), debate.currentRound, _agent, taskId);
    }

    function recordOracleOutput(address _contest, address _agent, uint256 _taskId, bytes calldata _output)
        external
        onlyOwner
        whenNotPaused
    {
        Debate storage debate = debates[_contest];
        if (debate.currentRound == 0 || debate.winner != address(0)) revert DebateNotActive(0);

        IJokeRaceContest contest = IJokeRaceContest(_contest);
        if (contest.state() != IJokeRaceContest.ContestState.Active) {
            revert ContestInvalidState(contest.state(), IJokeRaceContest.ContestState.Active);
        }

        if (_taskId == 0) revert TaskNotRequested();

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

        if (round.agent1Output.length > 0 && round.agent2Output.length > 0) {
            round.roundComplete = true;
            debate.currentRound++;
        }

        emit OracleOutputRecorded(0, debate.currentRound, _agent, _taskId, _output);
    }

    function terminateDebate(address _contest) external onlyOwner whenNotPaused {
        Debate storage debate = debates[_contest];
        if (debate.currentRound == 0 || debate.winner != address(0)) revert DebateNotActive(0);

        IJokeRaceContest contest = IJokeRaceContest(_contest);
        if (contest.state() != IJokeRaceContest.ContestState.Completed) {
            revert ContestInvalidState(contest.state(), IJokeRaceContest.ContestState.Completed);
        }

        uint256[] memory proposalIds = contest.getAllProposalIds();
        (address winner, uint256 winningVotes) = _determineWinner(contest, proposalIds, debate.agent1, debate.agent2);

        if (winner == address(0)) revert InvalidAgent(address(0));

        debate.winner = winner;
        debate.currentRound = 0; // Mark as terminated

        emit DebateTerminated(0, winner, winningVotes);
    }

    /*//////////////////////////////////////////////////////////////
                           PAUSE FUNCTIONALITY
    //////////////////////////////////////////////////////////////*/

    /// @notice Pauses all debate operations
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses all debate operations
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getRoundForDebate(address _contest, uint256 _round) external view returns (RoundData memory) {
        return debates[_contest].rounds[_round];
    }

    function getLatestRoundForDebate(address _contest) external view returns (RoundData memory) {
        return debates[_contest].rounds[debates[_contest].currentRound];
    }

    function getDebateInfo(address _contest)
        external
        view
        returns (address agent1, address agent2, uint256 currentRound, address winner)
    {
        Debate storage debate = debates[_contest];
        return (debate.agent1, debate.agent2, debate.currentRound, debate.winner);
    }

    function getAgentDebates(address agent) external view returns (address[] memory) {
        return agentDebates[agent];
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _determineWinner(
        IJokeRaceContest _contest,
        uint256[] memory _proposalIds,
        address _agent1,
        address _agent2
    ) internal view returns (address winner, uint256 highestVotes) {
        for (uint256 i = 0; i < _proposalIds.length; i++) {
            (uint256 forVotes,) = _contest.proposalVotes(_proposalIds[i]);
            if (forVotes > highestVotes) {
                (address author,,) = _contest.proposals(_proposalIds[i]);
                if (author == _agent1 || author == _agent2) {
                    highestVotes = forVotes;
                    winner = author;
                }
            }
        }
    }
}
