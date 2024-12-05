# Swan
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/170a81d7fdcb6e8e1e1df26e3a5bd45ec4316d4a/src/Swan.sol)

**Inherits:**
[SwanManager](/src/SwanManager.sol/abstract.SwanManager.md), UUPSUpgradeable


## State Variables
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


### listings
To keep track of the assets for purchase.


```solidity
mapping(address asset => AssetListing) public listings;
```


### assetsPerBuyerRound
Keeps track of assets per buyer & round.


```solidity
mapping(address buyer => mapping(uint256 round => address[])) public assetsPerBuyerRound;
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
    address _buyerAgentFactory,
    address _swanAssetFactory
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


### createBuyer

Creates a new buyer agent.

*Emits a `BuyerCreated` event.*


```solidity
function createBuyer(string calldata _name, string calldata _description, uint96 _feeRoyalty, uint256 _amountPerRound)
    external
    returns (BuyerAgent);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`BuyerAgent`|address of the new buyer agent.|


### list

Creates a new Asset.


```solidity
function list(string calldata _name, string calldata _symbol, bytes calldata _desc, uint256 _price, address _buyer)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_name`|`string`|name of the token.|
|`_symbol`|`string`|symbol of the token.|
|`_desc`|`bytes`|description of the token.|
|`_price`|`uint256`|price of the token.|
|`_buyer`|`address`|address of the buyer.|


### relist

Relist the asset for another round and/or another buyer and/or another price.


```solidity
function relist(address _asset, address _buyer, uint256 _price) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_asset`|`address`|address of the asset.|
|`_buyer`|`address`|new buyerAgent for the asset.|
|`_price`|`uint256`|new price of the token.|


### transferRoyalties

Function to transfer the royalties to the seller & Dria.


```solidity
function transferRoyalties(AssetListing storage asset) internal;
```

### purchase

Executes the purchase of a listing for a buyer for the given asset.

*Must be called by the buyer of the given asset.*


```solidity
function purchase(address _asset) external;
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


### getListingPrice

Returns the asset price with the given asset address.


```solidity
function getListingPrice(address _asset) external view returns (uint256);
```

### getListedAssets

Returns the number of assets with the given buyer and round.


```solidity
function getListedAssets(address _buyer, uint256 _round) external view returns (address[] memory);
```

### getListing

Returns the asset listing with the given asset address.


```solidity
function getListing(address _asset) external view returns (AssetListing memory);
```

## Events
### AssetListed
`asset` is created & listed for sale.


```solidity
event AssetListed(address indexed owner, address indexed asset, uint256 price);
```

### AssetRelisted
Asset relisted by it's `owner`.

*This may happen if a listed asset is not sold in the current round, and is relisted in a new round.*


```solidity
event AssetRelisted(address indexed owner, address indexed buyer, address indexed asset, uint256 price);
```

### AssetSold
A `buyer` purchased an Asset.


```solidity
event AssetSold(address indexed owner, address indexed buyer, address indexed asset, uint256 price);
```

### BuyerCreated
A new buyer agent is created.

*`owner` is the owner of the buyer agent.*

*`buyer` is the address of the buyer agent.*


```solidity
event BuyerCreated(address indexed owner, address indexed buyer);
```

## Errors
### InvalidStatus
Invalid asset status.


```solidity
error InvalidStatus(AssetStatus have, AssetStatus want);
```

### Unauthorized
Caller is not authorized for the operation, e.g. not a contract owner or listing owner.


```solidity
error Unauthorized(address caller);
```

### RoundNotFinished
The given asset is still in the given round.

*Most likely coming from `relist` function, where the asset cant be
relisted in the same round that it was listed in.*


```solidity
error RoundNotFinished(address asset, uint256 round);
```

### AssetLimitExceeded
Asset count limit exceeded for this round


```solidity
error AssetLimitExceeded(uint256 limit);
```

### InvalidPrice
Invalid price for the asset.


```solidity
error InvalidPrice(uint256 price);
```

## Structs
### AssetListing
Holds the listing information.

*`createdAt` is the timestamp of the Asset creation.*

*`feeRoyalty` is the royalty fee of the buyerAgent.*

*`price` is the price of the Asset.*

*`seller` is the address of the creator of the Asset.*

*`buyer` is the address of the buyerAgent.*

*`round` is the round in which the Asset is created.*

*`status` is the status of the Asset.*


```solidity
struct AssetListing {
    uint256 createdAt;
    uint96 feeRoyalty;
    uint256 price;
    address seller;
    address buyer;
    uint256 round;
    AssetStatus status;
}
```

## Enums
### AssetStatus
Status of an asset. All assets are listed as soon as they are listed.

*Unlisted: cannot be purchased in the current round.*

*Listed: can be purchase in the current round.*

*Sold: asset is sold.*

*It is important that `Unlisted` is only the default and is not set explicitly.
This allows to understand that if an asset is `Listed` but the round has past, it was not sold.
The said fact is used within the `relist` logic.*


```solidity
enum AssetStatus {
    Unlisted,
    Listed,
    Sold
}
```

