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

    /// @notice Sort proposals by votes (ascending order)
    function setSortedAndTiedProposals() external override {
        uint256 length = _proposalIds.length;
        _sortedProposals = _proposalIds; // Copy proposal IDs

        for (uint256 i = 0; i < length; i++) {
            for (uint256 j = i + 1; j < length; j++) {
                if (_votes[_sortedProposals[i]] > _votes[_sortedProposals[j]]) {
                    (_sortedProposals[i], _sortedProposals[j]) = (_sortedProposals[j], _sortedProposals[i]);
                }
            }
        }
    }

    /// @notice Returns sorted proposal IDs based on votes
    function sortedProposalIds() external view override returns (uint256[] memory) {
        return _sortedProposals;
    }
}
