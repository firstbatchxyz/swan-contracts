# SwanManager
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/ceefa4b0353ce4c0f1536b7318fa82b208305342/contracts/swan/SwanManager.sol)

**Inherits:**
OwnableUpgradeable


## State Variables
### marketParameters
Market parameters such as intervals and fees.


```solidity
SwanMarketParameters[] marketParameters;
```


### oracleParameters
Oracle parameters such as fees.


```solidity
LLMOracleTaskParameters oracleParameters;
```


### buyerAgentFactory
Factory contract to deploy Buyer Agents.


```solidity
BuyerAgentFactory public buyerAgentFactory;
```


### swanAssetFactory
Factory contract to deploy SwanAsset tokens.


```solidity
SwanAssetFactory public swanAssetFactory;
```


### coordinator
LLM Oracle Coordinator.


```solidity
LLMOracleCoordinator public coordinator;
```


### token
The token to be used for fee payments.


```solidity
ERC20 public token;
```


### isOperator
Operator addresses that can take actions on behalf of Buyer agents,
such as calling `purchase`, or `updateState` for them.


```solidity
mapping(address operator => bool) public isOperator;
```


## Functions
### constructor

Locks the contract, preventing any future re-initialization.

*[See more](https://docs.openzeppelin.com/contracts/5.x/api/proxy#Initializable-_disableInitializers--).*

**Note:**
oz-upgrades-unsafe-allow: constructor


```solidity
constructor();
```

### __SwanManager_init


```solidity
function __SwanManager_init(address _owner) public onlyInitializing;
```

### getMarketParameters

Returns the market parameters in memory.


```solidity
function getMarketParameters() external view returns (SwanMarketParameters[] memory);
```

### getOracleParameters

Returns the oracle parameters in memory.


```solidity
function getOracleParameters() external view returns (LLMOracleTaskParameters memory);
```

### setMarketParameters

Pushes a new market parameters to the marketParameters array.

*Only callable by owner.*


```solidity
function setMarketParameters(SwanMarketParameters memory _marketParameters) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_marketParameters`|`SwanMarketParameters`|new market parameters|


### setOracleParameters

Set the oracle parameters.

*Only callable by owner.*


```solidity
function setOracleParameters(LLMOracleTaskParameters calldata _oracleParameters) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_oracleParameters`|`LLMOracleTaskParameters`|new oracle parameters|


### getOracleFee

Returns the total fee required to make an oracle request.

*This is mainly required by the buyer to calculate its minimum fund amount, so that it can pay the fee.*


```solidity
function getOracleFee() external view returns (uint256);
```

### setFactories

Set the factories for Buyer Agents and Swan Assets.

*Only callable by owner.*


```solidity
function setFactories(address _buyerAgentFactory, address _swanAssetFactory) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_buyerAgentFactory`|`address`|new BuyerAgentFactory address|
|`_swanAssetFactory`|`address`|new SwanAssetFactory address|


### addOperator

Adds an operator that can take actions on behalf of Buyer agents.

*Only callable by owner.*

*Has no effect if the operator is already authorized.*


```solidity
function addOperator(address _operator) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_operator`|`address`|new operator address|


### removeOperator

Removes an operator, so that they are no longer authorized.

*Only callable by owner.*

*Has no effect if the operator is already not authorized.*


```solidity
function removeOperator(address _operator) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_operator`|`address`|operator address to remove|


### getCurrentMarketParameters

Returns the current market parameters.

*Current market parameters = Last element in the marketParameters array*


```solidity
function getCurrentMarketParameters() public view returns (SwanMarketParameters memory);
```

