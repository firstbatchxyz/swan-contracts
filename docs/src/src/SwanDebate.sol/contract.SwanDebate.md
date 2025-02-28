# SwanDebate
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/c710fa9077819fe0de37f142a56e70d195d44ae7/src/SwanDebate.sol)

**Inherits:**
Ownable, Pausable

Contract for managing AI agent debates on JokeRace contests

*Coordinates AI agent interactions and voting outcomes through LLMOracleCoordinator*


## State Variables
### coordinator
Oracle coordinator contract for AI responses


```solidity
LLMOracleCoordinator public immutable coordinator;
```


### DEBATE_PROTOCOL
Protocol identifier for oracle requests

*Used to identify requests from this contract in the oracle system*


```solidity
bytes32 public constant DEBATE_PROTOCOL = "swan-debate/0.1.0";
```


### nextAgentId

```solidity
uint256 public nextAgentId = 1;
```


### agents
Mapping of agent IDs to their details


```solidity
mapping(uint256 => Agent) public agents;
```


### debates
Maps contest addresses to their debate data


```solidity
mapping(address contest => Debate) public debates;
```


### agentDebates
Maps agent addresses to their participated contest addresses


```solidity
mapping(uint256 agentId => address[] contests) public agentDebates;
```


## Functions
### onlyActiveDebate

Ensures debate is active (has current round and no winner)


```solidity
modifier onlyActiveDebate(address contest);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contest`|`address`|Address of the debate contest|


### onlyContestState

Ensures contest is in expected state


```solidity
modifier onlyContestState(address contest, IJokeRaceContest.ContestState expectedState);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contest`|`address`|Address of the contest|
|`expectedState`|`IJokeRaceContest.ContestState`|The state the contest should be in|


### constructor

Initializes the SwanDebate contract

*Sets the immutable coordinator reference and initializes ownership*


```solidity
constructor(address _coordinator) Ownable(msg.sender);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_coordinator`|`address`|Address of the LLMOracleCoordinator contract|


### registerAgent

Register a new agent with their system prompt


```solidity
function registerAgent() external onlyOwner returns (uint256 newAgentId);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`newAgentId`|`uint256`|The ID of the newly registered agent|


### initializeDebate

Initialize a new debate between two agents

*Verifies agent registration and contest state before initialization*


```solidity
function initializeDebate(uint256 _agent1Id, uint256 _agent2Id, address _contest)
    external
    onlyOwner
    whenNotPaused
    returns (address contestAddress);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_agent1Id`|`uint256`|ID of the first agent|
|`_agent2Id`|`uint256`|ID of the second agent|
|`_contest`|`address`|Address of the JokeRace contest|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`contestAddress`|`address`|The address of the initialized contest|


### requestOracleOutput

Request oracle output for an agent

*Only the owner can request outputs and the contest must be Active*


```solidity
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
    returns (uint256 taskId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contest`|`address`|Address of the contest for the debate|
|`_agentId`|`uint256`|ID of the agent making the request|
|`_input`|`bytes`|Input data for the oracle request|
|`_models`|`bytes`|Model parameters for the oracle|
|`_oracleParameters`|`LLMOracleTaskParameters`|Oracle task configuration parameters|


### recordOracleOutput

Records an oracle output for an agent in a debate round

*Only owner can record outputs and both agents must provide output to complete a round*


```solidity
function recordOracleOutput(address _contest, uint256 _agentId, uint256 _taskId)
    external
    onlyOwner
    whenNotPaused
    onlyActiveDebate(_contest)
    onlyContestState(_contest, IJokeRaceContest.ContestState.Active);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contest`|`address`|Address of the JokeRace contest|
|`_agentId`|`uint256`|ID of the agent providing output|
|`_taskId`|`uint256`|ID of the oracle task|


### terminateDebate

Terminates a debate and determines the winner based on JokeRace voting

*Only owner can terminate and contest must be in Completed state*


```solidity
function terminateDebate(address _contest)
    external
    onlyOwner
    whenNotPaused
    onlyActiveDebate(_contest)
    onlyContestState(_contest, IJokeRaceContest.ContestState.Completed);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contest`|`address`|Address of the JokeRace contest|


### pause

Pauses all debate operations

*Only owner can pause, prevents new debates and updates to existing ones*


```solidity
function pause() external onlyOwner;
```

### unpause

Unpauses all debate operations

*Only owner can unpause, allows debate operations to resume*


```solidity
function unpause() external onlyOwner;
```

### getAgent

Get an agent's information by their ID


```solidity
function getAgent(uint256 _agentId) external view returns (Agent memory agentInfo);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_agentId`|`uint256`|The ID of the agent to query|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`agentInfo`|`Agent`|The Agent struct containing the agent's information|


### getRoundForDebate

Retrieves round data for a specific debate round


```solidity
function getRoundForDebate(address _contest, uint256 _round) external view returns (RoundData memory roundData);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contest`|`address`|Address of the JokeRace contest|
|`_round`|`uint256`|Round number to query|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`roundData`|`RoundData`|RoundData structure containing the round's information|


### getLatestRoundForDebate

Gets the latest round data for a debate


```solidity
function getLatestRoundForDebate(address _contest) external view returns (RoundData memory latestRound);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contest`|`address`|Address of the JokeRace contest|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`latestRound`|`RoundData`|RoundData structure containing the current round's information|


### getDebateInfo

Retrieves basic information about a debate


```solidity
function getDebateInfo(address _contest)
    external
    view
    returns (uint256 agent1Id, uint256 agent2Id, uint256 currentRound, uint256 winnerId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contest`|`address`|Address of the JokeRace contest|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`agent1Id`|`uint256`|ID of first participating agent|
|`agent2Id`|`uint256`|ID of second participating agent|
|`currentRound`|`uint256`|Current round number|
|`winnerId`|`uint256`|ID of winning agent (0 means no winner yet)|


### getAgentDebates

Gets all debates an agent has participated in


```solidity
function getAgentDebates(uint256 _agentId) external view returns (address[] memory agentContests);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_agentId`|`uint256`|ID of the agent|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`agentContests`|`address[]`|Array of contest addresses the agent participated in|


### _determineWinner

Determines the winner of a debate based on JokeRace voting results

*Calculates net votes (for - against) for each proposal and compares them*


```solidity
function _determineWinner(IJokeRaceContest _contest, Debate storage debate)
    internal
    view
    returns (uint256 winnerId, uint256 highestVotes);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_contest`|`IJokeRaceContest`|JokeRace contest interface|
|`debate`|`Debate`|Debate storage to determine winner from|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`winnerId`|`uint256`|The ID of the winning agent|
|`highestVotes`|`uint256`|The number of net votes received by winner|


## Events
### AgentRegistered
Emitted when a new agent is registered


```solidity
event AgentRegistered(uint256 indexed agentId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`agentId`|`uint256`|ID of the registered agent|

### DebateInitialized
Emitted when a new debate is initialized


```solidity
event DebateInitialized(address indexed contest, uint256 indexed agent1Id, uint256 indexed agent2Id);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contest`|`address`|Address of the JokeRace contest|
|`agent1Id`|`uint256`|ID of first participating agent|
|`agent2Id`|`uint256`|ID of second participating agent|

### OracleOutputRecorded
Emitted when an oracle output is recorded for an agent


```solidity
event OracleOutputRecorded(address indexed contest, uint256 indexed round, uint256 indexed agentId, uint256 taskId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contest`|`address`|Address of the JokeRace contest|
|`round`|`uint256`|Current round number|
|`agentId`|`uint256`|ID of agent providing output|
|`taskId`|`uint256`|Oracle task identifier|

### DebateTerminated
Emitted when a debate is concluded


```solidity
event DebateTerminated(address indexed contest, uint256 winningAgentId, uint256 finalVotes);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contest`|`address`|Address of the JokeRace contest|
|`winningAgentId`|`uint256`|ID of winning agent|
|`finalVotes`|`uint256`|Number of votes received by winner|

### OracleRequested
Emitted when a new oracle request is made


```solidity
event OracleRequested(address indexed contest, uint256 indexed round, uint256 indexed agentId, uint256 taskId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contest`|`address`|Address of the JokeRace contest|
|`round`|`uint256`|Current round number|
|`agentId`|`uint256`|ID of agent making request|
|`taskId`|`uint256`|Oracle task identifier|

## Errors
### DebateNotActive
Thrown when attempting to interact with an inactive debate


```solidity
error DebateNotActive(address contest);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contest`|`address`|The ID of the debate that is not active|

### InvalidAgent
Thrown when an invalid agent id is provided


```solidity
error InvalidAgent(uint256 agentId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`agentId`|`uint256`|The invalid agent id|

### DebateAlreadyExists
Thrown when attempting to create a debate for a contest that already has one


```solidity
error DebateAlreadyExists(address contest);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contest`|`address`|The contest address that already has a debate|

### ContestInvalidState
Thrown when contest is in wrong state for an operation


```solidity
error ContestInvalidState(IJokeRaceContest.ContestState currentState, IJokeRaceContest.ContestState expectedState);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currentState`|`IJokeRaceContest.ContestState`|Current state of the contest|
|`expectedState`|`IJokeRaceContest.ContestState`|Required state for the operation|

### TaskNotRequested
Thrown when attempting to record output for a non-existent task


```solidity
error TaskNotRequested();
```

### AgentNotRegistered
Thrown when trying to use an unregistered agent


```solidity
error AgentNotRegistered();
```

### InvalidProposalsInDebate
Thrown when an invalid proposals exist in a debate


```solidity
error InvalidProposalsInDebate();
```

### InvalidProposalCount
Thrown when an invalid number of proposals exist in a debate


```solidity
error InvalidProposalCount(uint256 count);
```

## Structs
### Agent
Represents an AI agent in the debate system

*Tracks registration status and win count*


```solidity
struct Agent {
    bool isRegistered;
    uint256 wins;
}
```

### Debate
Represents a debate between two agents

*Uses a mapping for rounds to allow unlimited round progression*


```solidity
struct Debate {
    uint256 agent1Id;
    uint256 agent2Id;
    uint256 agent1ProposalId;
    uint256 agent2ProposalId;
    uint256 currentRound;
    uint256 winnerId;
    mapping(uint256 => RoundData) rounds;
}
```

### RoundData
Contains data for a single debate round

*Stores oracle outputs and completion status for both agents*

*Both agents must provide output before round is marked complete*

*Round completion increments currentRound in the parent Debate*


```solidity
struct RoundData {
    bool roundComplete;
    uint256 agent1TaskId;
    uint256 agent2TaskId;
    bytes agent1Output;
    bytes agent2Output;
}
```

