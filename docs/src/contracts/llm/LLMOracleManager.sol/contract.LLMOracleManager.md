# LLMOracleManager
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/ceefa4b0353ce4c0f1536b7318fa82b208305342/contracts/llm/LLMOracleManager.sol)

**Inherits:**
OwnableUpgradeable

Holds the configuration for the LLM Oracle, such as allowed bounds on difficulty,
number of generations & validations, and fee settings.


## State Variables
### platformFee
A fixed fee paid for the platform.


```solidity
uint256 public platformFee;
```


### generationFee
The base fee factor for a generation of LLM generation.

*When scaled with difficulty & number of generations, we denote it as `generatorFee`.*


```solidity
uint256 public generationFee;
```


### validationFee
The base fee factor for a generation of LLM validation.

*When scaled with difficulty & number of validations, we denote it as `validatorFee`.*


```solidity
uint256 public validationFee;
```


### validationDeviationFactor
The deviation factor for the validation scores.


```solidity
uint64 public validationDeviationFactor;
```


### generationDeviationFactor
The deviation factor for the generation scores.


```solidity
uint64 public generationDeviationFactor;
```


### minimumParameters
Minimums for oracle parameters.


```solidity
LLMOracleTaskParameters minimumParameters;
```


### maximumParameters
Maximums for oracle parameters.


```solidity
LLMOracleTaskParameters maximumParameters;
```


## Functions
### __LLMOracleManager_init

Initialize the contract.


```solidity
function __LLMOracleManager_init(uint256 _platformFee, uint256 _generationFee, uint256 _validationFee)
    internal
    onlyInitializing;
```

### __LLMOracleManager_init_unchained


```solidity
function __LLMOracleManager_init_unchained(uint256 _platformFee, uint256 _generationFee, uint256 _validationFee)
    internal
    onlyInitializing;
```

### onlyValidParameters

Modifier to check if the given parameters are within the allowed range.


```solidity
modifier onlyValidParameters(LLMOracleTaskParameters calldata parameters);
```

### setFees

Update Oracle fees.

*To keep a fee unchanged, provide the same value.*


```solidity
function setFees(uint256 _platformFee, uint256 _generationFee, uint256 _validationFee) public onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_platformFee`|`uint256`|The new platform fee|
|`_generationFee`|`uint256`|The new generation fee|
|`_validationFee`|`uint256`|The new validation fee|


### getFee

Get the total fee for a given task setting.


```solidity
function getFee(LLMOracleTaskParameters calldata parameters)
    public
    view
    returns (uint256 totalFee, uint256 generatorFee, uint256 validatorFee);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`parameters`|`LLMOracleTaskParameters`|The task parameters.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`totalFee`|`uint256`|The total fee for the task.|
|`generatorFee`|`uint256`|The fee paid to each generator per generation.|
|`validatorFee`|`uint256`|The fee paid to each validator per validated generation.|


### setParameters

Update Oracle parameters bounds.

*Provide the same value to keep it unchanged.*


```solidity
function setParameters(LLMOracleTaskParameters calldata minimums, LLMOracleTaskParameters calldata maximums)
    public
    onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`minimums`|`LLMOracleTaskParameters`|The new minimum parameters.|
|`maximums`|`LLMOracleTaskParameters`|The new maximum parameters.|


### setDeviationFactors

Update deviation factors.

*Provide the same value to keep it unchanged.*


```solidity
function setDeviationFactors(uint64 _generationDeviationFactor, uint64 _validationDeviationFactor) public onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_generationDeviationFactor`|`uint64`|The new generation deviation factor.|
|`_validationDeviationFactor`|`uint64`|The new validation deviation factor.|


## Errors
### InvalidParameterRange
Given parameter is out of range.


```solidity
error InvalidParameterRange(uint256 have, uint256 min, uint256 max);
```

