// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SwanAgent} from "./SwanAgent.sol";
import {LLMOracleCoordinator} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";

/// @notice Interface for JokeRace contest interactions
interface IJokeRaceContest {
    enum ContestState {
        NotStarted,
        Active,
        Canceled,
        Queued,
        Completed
    }

    function state() external view returns (ContestState);
    function proposalVotes(uint256 proposalId) external view returns (uint256 forVotes, uint256 againstVotes);
    function getAllProposalIds() external view returns (uint256[] memory);
    function proposals(uint256 proposalId)
        external
        view
        returns (address author, bool exists, string memory description);
}

/// @title SwanDebate
/// @notice Manages debates between Swan agents using JokeRace for contest handling
/// @dev Core contract for managing AI agent debates and recording oracle outputs
contract SwanDebate is Ownable, Pausable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error DebateNotActive();
    error InvalidAgent();
    error DebateAlreadyExists();
    error ContestInvalidState();

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

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    struct Debate {
        address agent1;
        address agent2;
        address jokeRaceContest;
        uint256 currentRound;
        bool isActive;
        address winner;
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

    uint256 public debateCounter;
    mapping(uint256 => Debate) public debates;
    mapping(address => uint256) public jokeRaceToDebate;

    mapping(address => uint256[]) public agentDebates;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _coordinator) Ownable(msg.sender) {
        coordinator = LLMOracleCoordinator(_coordinator);
    }

    /*//////////////////////////////////////////////////////////////
                              CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes a new debate between two agents
    /// @param _agent1 Address of first agent
    /// @param _agent2 Address of second agent
    /// @param _jokeRaceContest Address of JokeRace contest
    function initializeDebate(address _agent1, address _agent2, address _jokeRaceContest)
        external
        onlyOwner
        returns (uint256 debateId)
    {
        if (_agent1 == address(0) || _agent2 == address(0)) revert InvalidAgent();
        if (jokeRaceToDebate[_jokeRaceContest] != 0) revert DebateAlreadyExists();

        IJokeRaceContest contest = IJokeRaceContest(_jokeRaceContest);
        if (contest.state() != IJokeRaceContest.ContestState.Queued) {
            revert ContestInvalidState();
        }

        debateId = ++debateCounter;
        Debate storage debate = debates[debateId];

        debate.agent1 = _agent1;
        debate.agent2 = _agent2;
        debate.jokeRaceContest = _jokeRaceContest;
        debate.isActive = true;
        debate.currentRound = 1;

        jokeRaceToDebate[_jokeRaceContest] = debateId;

        // track agent debates
        agentDebates[_agent1].push(debateId);
        agentDebates[_agent2].push(debateId);

        emit DebateInitialized(debateId, _agent1, _agent2, _jokeRaceContest);
    }

    /// @notice Records oracle output for a debate round
    /// @param _debateId ID of the debate
    /// @param _agent Address of the agent
    /// @param _taskId Oracle task ID
    /// @param _output Oracle output data
    function recordOracleOutput(uint256 _debateId, address _agent, uint256 _taskId, bytes calldata _output)
        external
        onlyOwner
    {
        Debate storage debate = debates[_debateId];
        if (!debate.isActive) revert DebateNotActive();

        IJokeRaceContest contest = IJokeRaceContest(debate.jokeRaceContest);
        if (contest.state() != IJokeRaceContest.ContestState.Active) {
            revert ContestInvalidState();
        }

        RoundData storage round = debate.rounds[debate.currentRound];

        if (_agent == debate.agent1) {
            round.agent1TaskId = _taskId;
            round.agent1Output = _output;
        } else if (_agent == debate.agent2) {
            round.agent2TaskId = _taskId;
            round.agent2Output = _output;
        } else {
            revert InvalidAgent();
        }

        if (round.agent1Output.length > 0 && round.agent2Output.length > 0) {
            round.roundComplete = true;
            debate.currentRound++;
        }

        emit OracleOutputRecorded(_debateId, debate.currentRound, _agent, _taskId, _output);
    }

    /// @notice Terminates a debate based on JokeRace contest results
    /// @param _debateId ID of the debate to terminate
    function terminateDebate(uint256 _debateId) external onlyOwner {
        Debate storage debate = debates[_debateId];
        if (!debate.isActive) revert DebateNotActive();

        IJokeRaceContest contest = IJokeRaceContest(debate.jokeRaceContest);
        if (contest.state() != IJokeRaceContest.ContestState.Completed) {
            revert ContestInvalidState();
        }

        uint256[] memory proposalIds = contest.getAllProposalIds();
        (address winner, uint256 winningVotes) = _determineWinner(contest, proposalIds, debate.agent1, debate.agent2);

        if (winner == address(0)) revert InvalidAgent();

        debate.isActive = false;
        debate.winner = winner;

        emit DebateTerminated(_debateId, winner, winningVotes);
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

    /// @notice Returns round data for a specific debate round
    function getRoundData(uint256 _debateId, uint256 _round)
        external
        view
        returns (
            uint256 agent1TaskId,
            uint256 agent2TaskId,
            bytes memory agent1Output,
            bytes memory agent2Output,
            bool roundComplete
        )
    {
        RoundData storage round = debates[_debateId].rounds[_round];
        return (round.agent1TaskId, round.agent2TaskId, round.agent1Output, round.agent2Output, round.roundComplete);
    }

    /// @notice Returns basic debate information
    function getDebateInfo(uint256 _debateId)
        external
        view
        returns (
            address agent1,
            address agent2,
            address jokeRaceContest,
            uint256 currentRound,
            bool isActive,
            address winner
        )
    {
        Debate storage debate = debates[_debateId];
        return
            (debate.agent1, debate.agent2, debate.jokeRaceContest, debate.currentRound, debate.isActive, debate.winner);
    }

    /// @notice Returns all debate IDs an agent has participated in
    /// @param agent Address of the agent
    /// @return Array of debate IDs
    function getAgentDebates(address agent) external view returns (uint256[] memory) {
        return agentDebates[agent];
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Determines the winner of a debate from JokeRace votes
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
