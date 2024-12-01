# LLMOracleTaskParameters
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/ceefa4b0353ce4c0f1536b7318fa82b208305342/contracts/llm/LLMOracleTask.sol)

Collection of oracle task-related parameters.

*Prevents stack-too-deep with tight-packing.
TODO: use 256-bit tight-packing here*


```solidity
struct LLMOracleTaskParameters {
    uint8 difficulty;
    uint40 numGenerations;
    uint40 numValidations;
}
```

