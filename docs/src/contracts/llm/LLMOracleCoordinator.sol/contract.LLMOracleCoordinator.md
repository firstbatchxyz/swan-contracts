# LLMOracleCoordinator
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/ceefa4b0353ce4c0f1536b7318fa82b208305342/contracts/llm/LLMOracleCoordinator.sol)

**Inherits:**
[LLMOracleTask](/contracts/llm/LLMOracleTask.sol/interface.LLMOracleTask.md), [LLMOracleManager](/contracts/llm/LLMOracleManager.sol/contract.LLMOracleManager.md), UUPSUpgradeable

Responsible for coordinating the Oracle responses to LLM generation requests.


## State Variables
### registry
The Oracle Registry.


```solidity
LLMOracleRegistry public registry;
```


### feeToken
The token to be used for fee payments.


```solidity
ERC20 public feeToken;
```


### nextTaskId
The task ID counter.

*TaskId starts from 1, as 0 is reserved.*

*0 can be used in to check that a request/response/validation has not been made.*


```solidity
uint256 public nextTaskId;
```


### requests
LLM generation requests.


```solidity
mapping(uint256 taskId => TaskRequest) public requests;
```


### responses
LLM generation responses.


```solidity
mapping(uint256 taskId => TaskResponse[]) public responses;
```


### validations
LLM generation response validations.


```solidity
mapping(uint256 taskId => TaskValidation[]) public validations;
```


## Functions
### onlyRegistered

Reverts if `msg.sender` is not a registered oracle.


```solidity
modifier onlyRegistered(LLMOracleKind kind);
```

### onlyAtStatus

Reverts if the task status is not `status`.


```solidity
modifier onlyAtStatus(uint256 taskId, TaskStatus status);
```

### constructor

Locks the contract, preventing any future re-initialization.

*[See more](https://docs.openzeppelin.com/contracts/5.x/api/proxy#Initializable-_disableInitializers--).*

**Note:**
oz-upgrades-unsafe-allow: constructor


```solidity
constructor();
```

### _authorizeUpgrade

Function that should revert when `msg.sender` is not authorized to upgrade the contract.

*Called by and upgradeToAndCall.*


```solidity
function _authorizeUpgrade(address newImplementation) internal override onlyOwner;
```

### initialize

Initialize the contract.

Sets the Oracle Registry & Oracle Fee Manager.


```solidity
function initialize(
    address _oracleRegistry,
    address _feeToken,
    uint256 _platformFee,
    uint256 _generationFee,
    uint256 _validationFee
) public initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_oracleRegistry`|`address`|The Oracle Registry contract address.|
|`_feeToken`|`address`|The token (ERC20) to be used for fee payments (usually $BATCH).|
|`_platformFee`|`uint256`|The initial platform fee for each LLM generation.|
|`_generationFee`|`uint256`|The initial base fee for LLM generation.|
|`_validationFee`|`uint256`|The initial base fee for response validation.|


### request

Request LLM generation.

*Input must be non-empty.*

*Reverts if contract has not enough allowance for the fee.*

*Reverts if difficulty is out of range.*


```solidity
function request(bytes32 protocol, bytes memory input, bytes memory models, LLMOracleTaskParameters calldata parameters)
    public
    onlyValidParameters(parameters)
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`protocol`|`bytes32`|The protocol string, should be a short 32-byte string (e.g., "dria/1.0.0").|
|`input`|`bytes`|The input data for the LLM generation.|
|`models`|`bytes`||
|`parameters`|`LLMOracleTaskParameters`|The task parameters|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|task id|


### respond

Respond to an LLM generation.

*Output must be non-empty.*

*Reverts if the task is not pending generation.*

*Reverts if the responder is not registered.*

*Reverts if the responder has already responded to this task.*

*Reverts if the nonce is not a valid proof-of-work.*


```solidity
function respond(uint256 taskId, uint256 nonce, bytes calldata output, bytes calldata metadata)
    public
    onlyRegistered(LLMOracleKind.Generator)
    onlyAtStatus(taskId, TaskStatus.PendingGeneration);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`taskId`|`uint256`|The task ID to respond to.|
|`nonce`|`uint256`|The proof-of-work nonce.|
|`output`|`bytes`|The output data for the LLM generation.|
|`metadata`|`bytes`|Optional metadata for this output.|


### validate

Validate requests for a given taskId.

*Reverts if the task is not pending validation.*

*Reverts if the number of scores is not equal to the number of generations.*

*Reverts if any score is greater than the maximum score.*


```solidity
function validate(uint256 taskId, uint256 nonce, uint256[] calldata scores, bytes calldata metadata)
    public
    onlyRegistered(LLMOracleKind.Validator)
    onlyAtStatus(taskId, TaskStatus.PendingValidation);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`taskId`|`uint256`|The ID of the task to validate.|
|`nonce`|`uint256`|The proof-of-work nonce.|
|`scores`|`uint256[]`|The validation scores for each generation.|
|`metadata`|`bytes`|Optional metadata for this validation.|


### assertValidNonce

Checks that proof-of-work is valid for a given task with taskId and nonce.

*Reverts if the nonce is not a valid proof-of-work.*


```solidity
function assertValidNonce(uint256 taskId, TaskRequest storage task, uint256 nonce) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`taskId`|`uint256`|The ID of the task to check proof-of-work.|
|`task`|`TaskRequest`|The task (in storage) to validate.|
|`nonce`|`uint256`|The candidate proof-of-work nonce.|


### finalizeValidation

Compute the validation scores for a given task.

*Reverts if the task has no validations.*


```solidity
function finalizeValidation(uint256 taskId) private;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`taskId`|`uint256`|The ID of the task to compute scores for.|


### withdrawPlatformFees

Withdraw the platform fees & along with remaining fees within the contract.


```solidity
function withdrawPlatformFees() public onlyOwner;
```

### getResponses

Returns the responses to a given taskId.


```solidity
function getResponses(uint256 taskId) public view returns (TaskResponse[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`taskId`|`uint256`|The ID of the task to get responses for.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`TaskResponse[]`|The responses for the given taskId.|


### getValidations

Returns the validations to a given taskId.


```solidity
function getValidations(uint256 taskId) public view returns (TaskValidation[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`taskId`|`uint256`|The ID of the task to get validations for.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`TaskValidation[]`|The validations for the given taskId.|


### _increaseAllowance

Increases the allowance by setting the approval to the sum of the current allowance and the additional amount.


```solidity
function _increaseAllowance(address spender, uint256 amount) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`spender`|`address`|spender address|
|`amount`|`uint256`|additional amount of allowance|


### getBestResponse

Returns the best performing result of the given task.

*For invalid task IDs, the status check will fail.*


```solidity
function getBestResponse(uint256 taskId) external view returns (TaskResponse memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`taskId`|`uint256`|The ID of the task to get the result for.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`TaskResponse`|The best performing response w.r.t validation scores.|


## Events
### Request
Indicates a generation request for LLM.

*`protocol` is a short 32-byte string (e.g., "dria/1.0.0").*

*Using the protocol topic, listeners can filter by protocol.*


```solidity
event Request(uint256 indexed taskId, address indexed requester, bytes32 indexed protocol);
```

### Response
Indicates a single Oracle response for a request.


```solidity
event Response(uint256 indexed taskId, address indexed responder);
```

### Validation
Indicates a single Oracle response for a request.


```solidity
event Validation(uint256 indexed taskId, address indexed validator);
```

### StatusUpdate
Indicates the status change of an LLM generation request.


```solidity
event StatusUpdate(uint256 indexed taskId, bytes32 indexed protocol, TaskStatus statusBefore, TaskStatus statusAfter);
```

## Errors
### InsufficientFees
Not enough funds were provided for the task.


```solidity
error InsufficientFees(uint256 have, uint256 want);
```

### InvalidTaskStatus
Unexpected status for this task.


```solidity
error InvalidTaskStatus(uint256 taskId, TaskStatus have, TaskStatus want);
```

### InvalidNonce
The given nonce is not a valid proof-of-work.


```solidity
error InvalidNonce(uint256 taskId, uint256 nonce);
```

### InvalidValidation
The provided validation does not have a score for all responses.


```solidity
error InvalidValidation(uint256 taskId, address validator);
```

### NotRegistered
The oracle is not registered.


```solidity
error NotRegistered(address oracle);
```

### AlreadyResponded
The oracle has already responded to this task.


```solidity
error AlreadyResponded(uint256 taskId, address oracle);
```

