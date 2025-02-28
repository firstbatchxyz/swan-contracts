# IJokeRaceContest
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/c710fa9077819fe0de37f142a56e70d195d44ae7/src/SwanDebate.sol)

Interface for JokeRace contest interactions

*Provides functions to interact with JokeRace contests and query their state*


## Functions
### state

Returns current contest state


```solidity
function state() external view returns (ContestState);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`ContestState`|Current state of the contest|


### proposalVotes

Returns vote counts for a proposal


```solidity
function proposalVotes(uint256 proposalId) external view returns (uint256 forVotes, uint256 againstVotes);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The ID of the proposal to query|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`forVotes`|`uint256`|Number of votes in favor|
|`againstVotes`|`uint256`|Number of votes against|


### getAllProposalIds

Returns all proposal IDs in the contest


```solidity
function getAllProposalIds() external view returns (uint256[] memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256[]`|Array of proposal IDs|


### proposals

Returns proposal details


```solidity
function proposals(uint256 proposalId) external view returns (address author, bool exists, string memory description);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proposalId`|`uint256`|The ID of the proposal to query|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`author`|`address`|Address that created the proposal|
|`exists`|`bool`|Whether the proposal exists|
|`description`|`string`|Text description of the proposal|


## Enums
### ContestState
Represents the current state of a contest

*Used to control valid operations at different stages*


```solidity
enum ContestState {
    NotStarted,
    Active,
    Canceled,
    Queued,
    Completed
}
```

