# BuyerAgent
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/170a81d7fdcb6e8e1e1df26e3a5bd45ec4316d4a/src/BuyerAgent.sol)

**Inherits:**
Ownable

BuyerAgent is responsible for buying the assets from Swan.


## State Variables
### swan
Swan contract.


```solidity
Swan public immutable swan;
```


### createdAt
Timestamp when the contract is deployed.


```solidity
uint256 public immutable createdAt;
```


### marketParameterIdx
Holds the index of the Swan market parameters at the time of deployment.

*When calculating the round, we will use this index to determine the start interval.*


```solidity
uint256 public immutable marketParameterIdx;
```


### name
Buyer agent name.


```solidity
string public name;
```


### description
Buyer agent description, can include backstory, behavior and objective together.


```solidity
string public description;
```


### state
State of the buyer agent.

*Only updated by the oracle via `updateState`.*


```solidity
bytes public state;
```


### feeRoyalty
Royalty fees for the buyer agent.


```solidity
uint96 public feeRoyalty;
```


### amountPerRound
The max amount of money the agent can spend per round.


```solidity
uint256 public amountPerRound;
```


### inventory
The assets that the buyer agent has.


```solidity
mapping(uint256 round => address[] assets) public inventory;
```


### spendings
Amount of money spent on each round.


```solidity
mapping(uint256 round => uint256 spending) public spendings;
```


### oraclePurchaseRequests
Oracle requests for each round about item purchases.

*A taskId of 0 means no request has been made.*


```solidity
mapping(uint256 round => uint256 taskId) public oraclePurchaseRequests;
```


### oracleStateRequests
Oracle requests for each round about buyer state updates.

*A taskId of 0 means no request has been made.*

*A non-zero taskId means a request has been made, but not necessarily processed.*

*To see if a task is completed, check `isOracleTaskProcessed`.*


```solidity
mapping(uint256 round => uint256 taskId) public oracleStateRequests;
```


### isOracleRequestProcessed
Indicates whether a given task has been processed.

*This is used to prevent double processing of the same task.*


```solidity
mapping(uint256 taskId => bool isProcessed) public isOracleRequestProcessed;
```


## Functions
### onlyAuthorized

Check if the caller is the owner, operator, or Swan.

*Swan is an operator itself, so the first check handles that as well.*


```solidity
modifier onlyAuthorized();
```

### constructor

Create the buyer agent.

*`_feeRoyalty` should be between 1 and maxBuyerAgentFee in the swan market parameters.*

*All tokens are approved to the oracle coordinator of operator.*


```solidity
constructor(
    string memory _name,
    string memory _description,
    uint96 _feeRoyalty,
    uint256 _amountPerRound,
    address _operator,
    address _owner
) Ownable(_owner);
```

### minFundAmount

The minimum amount of money that the buyer must leave within the contract.

*minFundAmount should be `amountPerRound + oracleFee` to be able to make requests.*


```solidity
function minFundAmount() public view returns (uint256);
```

### oracleResult

Reads the best performing result for a given task id, and parses it as an array of addresses.


```solidity
function oracleResult(uint256 taskId) public view returns (bytes memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`taskId`|`uint256`|task id to be read|


### oracleStateRequest

Calls the LLMOracleCoordinator & pays for the oracle fees to make a state update request.

*Works only in `Withdraw` phase.*

*Calling again in the same round will overwrite the previous request.
The operator must check that there is no request in beforehand,
so to not overwrite an existing request of the owner.*


```solidity
function oracleStateRequest(bytes calldata _input, bytes calldata _models) external onlyAuthorized;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_input`|`bytes`|input to the LLMOracleCoordinator.|
|`_models`|`bytes`|models to be used for the oracle.|


### oraclePurchaseRequest

Calls the LLMOracleCoordinator & pays for the oracle fees to make a purchase request.

*Works only in `Buy` phase.*

*Calling again in the same round will overwrite the previous request.
The operator must check that there is no request in beforehand,
so to not overwrite an existing request of the owner.*


```solidity
function oraclePurchaseRequest(bytes calldata _input, bytes calldata _models) external onlyAuthorized;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_input`|`bytes`|input to the LLMOracleCoordinator.|
|`_models`|`bytes`|models to be used for the oracle.|


### updateState

Function to update the Buyer state.

*Works only in `Withdraw` phase.*

*Can be called multiple times within a single round, although is not expected to be done so.*


```solidity
function updateState() external onlyAuthorized;
```

### purchase

Function to buy the asset from the Swan with the given assed address.

*Works only in `Buy` phase.*

*Can be called multiple times within a single round, although is not expected to be done so.*

*This is not expected to revert if the oracle works correctly.*


```solidity
function purchase() external onlyAuthorized;
```

### withdraw

Function to withdraw the tokens from the contract.

*If the current phase is `Withdraw` buyer can withdraw any amount of tokens.*

*If the current phase is not `Withdraw` buyer has to leave at least `minFundAmount` in the contract.*


```solidity
function withdraw(uint96 _amount) public onlyAuthorized;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_amount`|`uint96`|amount to withdraw.|


### treasury

Alias to get the token balance of buyer agent.


```solidity
function treasury() public view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|token balance|


### _checkRoundPhase

Checks that we are in the given phase, and returns both round and phase.


```solidity
function _checkRoundPhase(Phase _phase) internal view returns (uint256, Phase);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_phase`|`Phase`|expected phase.|


### _computeCycleTime

Computes cycle time by using intervals from given market parameters.

*Used in 'computePhase()' function.*


```solidity
function _computeCycleTime(SwanMarketParameters memory params) internal pure returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`SwanMarketParameters`|Market parameters of the Swan.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|the total cycle time that is `sellInterval + buyInterval + withdrawInterval`.|


### _computePhase

Function to compute the current round, phase and time until next phase w.r.t given market parameters.


```solidity
function _computePhase(SwanMarketParameters memory params, uint256 elapsedTime)
    internal
    pure
    returns (uint256, Phase, uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`SwanMarketParameters`|Market parameters of the Swan.|
|`elapsedTime`|`uint256`|Time elapsed that computed in 'getRoundPhase()' according to the timestamps of each round.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|round, phase, time until next phase|
|`<none>`|`Phase`||
|`<none>`|`uint256`||


### getRoundPhase

Function to return the current round, elapsed round and the current phase according to the current time.

*Each round is composed of three phases in order: Sell, Buy, Withdraw.*

*Internally, it computes the intervals from market parameters at the creation of this agent, until now.*

*If there are many parameter changes throughout the life of this agent, this may cost more GAS.*


```solidity
function getRoundPhase() public view returns (uint256, Phase, uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|round, phase, time until next phase|
|`<none>`|`Phase`||
|`<none>`|`uint256`||


### setFeeRoyalty

Function to set feeRoyalty.

*Only callable by the owner.*

*Only callable in withdraw phase.*


```solidity
function setFeeRoyalty(uint96 newFeeRoyalty) public onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newFeeRoyalty`|`uint96`|must be between 1 and 100.|


### setAmountPerRound

Function to set the amountPerRound.

*Only callable by the owner.*

*Only callable in withdraw phase.*


```solidity
function setAmountPerRound(uint256 _amountPerRound) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_amountPerRound`|`uint256`|new amountPerRound.|


## Events
### StateRequest
Emitted when a state update request is made.


```solidity
event StateRequest(uint256 indexed taskId, uint256 indexed round);
```

### PurchaseRequest
Emitted when a purchase request is made.


```solidity
event PurchaseRequest(uint256 indexed taskId, uint256 indexed round);
```

### Purchase
Emitted when a purchase is made.


```solidity
event Purchase(uint256 indexed taskId, uint256 indexed round);
```

### StateUpdate
Emitted when the state is updated.


```solidity
event StateUpdate(uint256 indexed taskId, uint256 indexed round);
```

## Errors
### MinFundSubceeded
The `value` is less than `minFundAmount`


```solidity
error MinFundSubceeded(uint256 value);
```

### InvalidFee
Given fee is invalid, e.g. not within the range.


```solidity
error InvalidFee(uint256 fee);
```

### BuyLimitExceeded
Asset count limit exceeded for this round


```solidity
error BuyLimitExceeded(uint256 have, uint256 want);
```

### InvalidPhase
Invalid phase


```solidity
error InvalidPhase(Phase have, Phase want);
```

### Unauthorized
Unauthorized caller.


```solidity
error Unauthorized(address caller);
```

### TaskNotRequested
No task request has been made yet.


```solidity
error TaskNotRequested();
```

### TaskAlreadyProcessed
The task was already processed, via `purchase` or `updateState`.


```solidity
error TaskAlreadyProcessed();
```

## Enums
### Phase
Phase of the purchase loop.


```solidity
enum Phase {
    Sell,
    Buy,
    Withdraw
}
```

