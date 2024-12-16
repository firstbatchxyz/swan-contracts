# Swan
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/feb8dd64d672a341a29a0a52b12cc56adf09c996/src/Swan.sol)

**Inherits:**
[SwanManager](/src/SwanManager.sol/abstract.SwanManager.md), UUPSUpgradeable


## State Variables
### agentFactory
Factory contract to deploy AI Agents.


```solidity
AIAgentFactory public agentFactory;
```


### artifactFactory
Factory contract to deploy Artifact tokens.


```solidity
ArtifactFactory public artifactFactory;
```


### listings
To keep track of the artifacts for purchase.


```solidity
mapping(address artifact => ArtifactListing) public listings;
```


### artifactsPerAgentRound
Keeps track of artifacts per agent & round.


```solidity
mapping(address agent => mapping(uint256 round => address[])) public artifactsPerAgentRound;
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

### _authorizeUpgrade

Upgrades to contract with a new implementation.

*Only callable by the owner.*


```solidity
function _authorizeUpgrade(address newImplementation) internal override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newImplementation`|`address`|address of the new implementation|


### initialize

Initialize the contract.


```solidity
function initialize(
    SwanMarketParameters calldata _marketParameters,
    LLMOracleTaskParameters calldata _oracleParameters,
    address _coordinator,
    address _token,
    address _agentFactory,
    address _artifactFactory
) public initializer;
```

### transferOwnership

Transfer ownership of the contract.

*Overrides the default `transferOwnership` function to make the new owner an operator.*


```solidity
function transferOwnership(address newOwner) public override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newOwner`|`address`|address of the new owner.|


### createAgent

Creates a new AI agent.

*Emits a `AIAgentCreated` event.*


```solidity
function createAgent(string calldata _name, string calldata _description, uint96 _feeRoyalty, uint256 _amountPerRound)
    external
    returns (AIAgent);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`AIAgent`|address of the new AI agent.|


### list

Creates a new artifact.


```solidity
function list(string calldata _name, string calldata _symbol, bytes calldata _desc, uint256 _price, address _agent)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_name`|`string`|name of the token.|
|`_symbol`|`string`|symbol of the token.|
|`_desc`|`bytes`|description of the token.|
|`_price`|`uint256`|price of the token.|
|`_agent`|`address`|address of the agent.|


### relist

Relist the artifact for another round and/or another agent and/or another price.


```solidity
function relist(address _artifact, address _agent, uint256 _price) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_artifact`|`address`|address of the artifact.|
|`_agent`|`address`|new AIAgent for the artifact.|
|`_price`|`uint256`|new price of the token.|


### transferRoyalties

Function to transfer the royalties to the seller & Dria.


```solidity
function transferRoyalties(ArtifactListing storage _artifact) internal;
```

### purchase

Executes the purchase of a listing for a agent for the given artifact.

*Must be called by the agent of the given artifact.*


```solidity
function purchase(address _artifact) external;
```

### setFactories

Set the factories for AI Agents and Artifacts.

*Only callable by owner.*


```solidity
function setFactories(address _agentFactory, address _artifactFactory) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_agentFactory`|`address`|new AIAgentFactory address|
|`_artifactFactory`|`address`|new ArtifactFactory address|


### getListingPrice

Returns the artifact price with the given artifact address.


```solidity
function getListingPrice(address _artifact) external view returns (uint256);
```

### getListedArtifacts

Returns the number of artifacts with the given agent and round.


```solidity
function getListedArtifacts(address _agent, uint256 _round) external view returns (address[] memory);
```

### getListing

Returns the artifact listing with the given artifact address.


```solidity
function getListing(address _artifact) external view returns (ArtifactListing memory);
```

## Events
### ArtifactListed
Artifact is created & listed for sale.


```solidity
event ArtifactListed(address indexed owner, address indexed artifact, uint256 price);
```

### ArtifactRelisted
Artifact relisted by it's `owner`.

*This may happen if a listed artifact is not sold in the current round, and is relisted in a new round.*


```solidity
event ArtifactRelisted(address indexed owner, address indexed agent, address indexed artifact, uint256 price);
```

### ArtifactSold
An `agent` purchased an artifact.


```solidity
event ArtifactSold(address indexed owner, address indexed agent, address indexed artifact, uint256 price);
```

### AIAgentCreated
A new AI agent is created.

*`owner` is the owner of the AI agent.*

*`agent` is the address of the AI agent.*


```solidity
event AIAgentCreated(address indexed owner, address indexed agent);
```

## Errors
### InvalidStatus
Invalid artifact status.


```solidity
error InvalidStatus(ArtifactStatus have, ArtifactStatus want);
```

### Unauthorized
Caller is not authorized for the operation, e.g. not a contract owner or listing owner.


```solidity
error Unauthorized(address caller);
```

### RoundNotFinished
The given artifact is still in the given round.

*Most likely coming from `relist` function, where the artifact cant be
relisted in the same round that it was listed in.*


```solidity
error RoundNotFinished(address artifact, uint256 round);
```

### ArtifactLimitExceeded
Artifact count limit exceeded for this round


```solidity
error ArtifactLimitExceeded(uint256 limit);
```

### InvalidPrice
Invalid price for the artifact.


```solidity
error InvalidPrice(uint256 price);
```

## Structs
### ArtifactListing
Holds the listing information.

*`createdAt` is the timestamp of the artifact creation.*

*`feeRoyalty` is the royalty fee of the AIAgent.*

*`price` is the price of the artifact.*

*`seller` is the address of the creator of the artifact.*

*`agent` is the address of the AIAgent.*

*`round` is the round in which the artifact is created.*

*`status` is the status of the artifact.*


```solidity
struct ArtifactListing {
    uint256 createdAt;
    uint96 feeRoyalty;
    uint256 price;
    address seller;
    address agent;
    uint256 round;
    ArtifactStatus status;
}
```

## Enums
### ArtifactStatus
Status of an artifact. All artifacts are listed as soon as they are listed.

*Unlisted: Cannot be purchased in the current round.*

*Listed: Can be purchase in the current round.*

*Sold: Artifact is sold.*

*It is important that `Unlisted` is only the default and is not set explicitly.
This allows to understand that if an artifact is `Listed` but the round has past, it was not sold.
The said fact is used within the `relist` logic.*


```solidity
enum ArtifactStatus {
    Unlisted,
    Listed,
    Sold
}
```

