// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {IJokeRaceContest} from "../../src/SwanDebate.sol";

/// @dev Mock implementation of `IJokeRaceContest`
contract MockJokeRaceContest is IJokeRaceContest {
    ContestState private _currentState;
    mapping(uint256 => uint256) private _votes;
    mapping(uint256 => address) private _authors;
    uint256[] private _proposalIds;
    uint256[] private _sortedProposals;

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

    function proposalVotes(uint256 proposalId) external view override returns (uint256 votes) {
        return (_votes[proposalId]);
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
