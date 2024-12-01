# LLMOracleTask
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/ceefa4b0353ce4c0f1536b7318fa82b208305342/contracts/llm/LLMOracleTask.sol)

An umbrella interface that captures task-related structs and enums.


## Structs
### TaskRequest
A task request for LLM generation.

*Fees are stored here as well in case fee changes occur within the duration of a task.*


```solidity
struct TaskRequest {
    address requester;
    bytes32 protocol;
    LLMOracleTaskParameters parameters;
    TaskStatus status;
    uint256 generatorFee;
    uint256 validatorFee;
    uint256 platformFee;
    bytes input;
    bytes models;
}
```

### TaskResponse
A task response to an LLM generation request.


```solidity
struct TaskResponse {
    address responder;
    uint256 nonce;
    uint256 score;
    bytes output;
    bytes metadata;
}
```

### TaskValidation
A task validation for a response.


```solidity
struct TaskValidation {
    address validator;
    uint256 nonce;
    uint256[] scores;
    bytes metadata;
}
```

## Enums
### TaskStatus
Task status.

*`None`: Task has not been created yet. (default)*

*`PendingGeneration`: Task is waiting for Oracle generation responses.*

*`PendingValidation`: Task is waiting for validation by validator Oracles.*

*`Completed`: The task has been completed.*

*With validation, the flow is `None -> PendingGeneration -> PendingValidation -> Completed`.*

*Without validation, the flow is `None -> PendingGeneration -> Completed`.*


```solidity
enum TaskStatus {
    None,
    PendingGeneration,
    PendingValidation,
    Completed
}
```

