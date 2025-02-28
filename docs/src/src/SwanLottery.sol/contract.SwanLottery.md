# SwanLottery
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/c710fa9077819fe0de37f142a56e70d195d44ae7/src/SwanLottery.sol)

**Inherits:**
Ownable


## State Variables
### BASIS_POINTS
*Used to calculate rewards and multipliers with proper decimal precision.*


```solidity
uint256 public constant BASIS_POINTS = 10000;
```


### swan
Main Swan contract instance.


```solidity
Swan public immutable swan;
```


### token
Token used for rewards and payments.


```solidity
ERC20 public immutable token;
```


### claimWindow
Number of rounds after listing that rewards can be claimed.


```solidity
uint256 public claimWindow;
```


### artifactMultipliers
Maps artifact to its assigned multiplier.


```solidity
mapping(address artifact => uint256 multiplier) public artifactMultipliers;
```


### rewardsClaimed
Tracks whether rewards have been claimed for an artifact.


```solidity
mapping(address artifact => bool claimed) public rewardsClaimed;
```


### authorized
Maps addresses to their authorization status for lottery operations.


```solidity
mapping(address addr => bool isAllowed) public authorized;
```


## Functions
### onlyAuthorized


```solidity
modifier onlyAuthorized();
```

### constructor

Constructor sets initial configuration

*Sets Swan contract, token, and initial claim window*


```solidity
constructor(address _swan, uint256 _claimWindow) Ownable(msg.sender);
```

### computeMultiplier

Public view of multiplier computation


```solidity
function computeMultiplier(address artifact) external view returns (uint256);
```

### _computeRandomness

Compute randomness for multiplier


```solidity
function _computeRandomness(address artifact) internal view returns (uint256);
```

### selectMultiplier

Select multiplier based on random value


```solidity
function selectMultiplier(uint256 rand) public pure returns (uint256);
```

### claimRewards

Claims rewards for sold artifacts within claim window


```solidity
function claimRewards(address artifact) external onlyAuthorized;
```

### getRewards

Calculate potential reward for an artifact.


```solidity
function getRewards(address artifact) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`artifact`|`address`|The address of the artifact.|


### setAuthorization

Update authorization status.

*Only owner can call.*


```solidity
function setAuthorization(address addr, bool status) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`addr`|`address`|The address to update authorization status for.|
|`status`|`bool`|The new authorization status.|


### setClaimWindow

Update claim window.

*Only owner can call.*


```solidity
function setClaimWindow(uint256 newWindow) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newWindow`|`uint256`|The new claim window duration.|


## Events
### AuthorizationUpdated
Emitted when an address's authorization status is updated.


```solidity
event AuthorizationUpdated(address indexed addr, bool status);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`addr`|`address`|The address whose authorization was updated.|
|`status`|`bool`|The new authorization status.|

### MultiplierAssigned
Emitted when a multiplier is assigned to an artifact.


```solidity
event MultiplierAssigned(address indexed artifact, uint256 multiplier);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`artifact`|`address`|The address of the artifact.|
|`multiplier`|`uint256`|The assigned multiplier value.|

### RewardClaimed
Emitted when a reward is claimed for an artifact.


```solidity
event RewardClaimed(address indexed seller, address indexed artifact, uint256 reward);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`seller`|`address`|The address of the artifact seller.|
|`artifact`|`address`|The address of the artifact.|
|`reward`|`uint256`|The amount of reward claimed.|

### ClaimWindowUpdated
Emitted when the claim window duration is updated.


```solidity
event ClaimWindowUpdated(uint256 oldWindow, uint256 newWindow);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`oldWindow`|`uint256`|Previous claim window value.|
|`newWindow`|`uint256`|New claim window value.|

## Errors
### Unauthorized
Caller is not authorized for the operation.


```solidity
error Unauthorized(address caller);
```

### InvalidClaimWindow
Invalid claim window value provided.


```solidity
error InvalidClaimWindow();
```

### MultiplierAlreadyAssigned
Multiplier has already been assigned for this artifact and round.


```solidity
error MultiplierAlreadyAssigned(address artifact, uint256 round);
```

### RewardAlreadyClaimed
Reward has already been claimed for this artifact.


```solidity
error RewardAlreadyClaimed(address artifact);
```

### ClaimWindowExpired
Claim window has expired for the artifact.


```solidity
error ClaimWindowExpired(uint256 currentRound, uint256 listingRound, uint256 window);
```

### InvalidArtifact
Invalid artifact address provided.


```solidity
error InvalidArtifact(address artifact);
```

### ArtifactNotSold
Artifact is not in sold status.


```solidity
error ArtifactNotSold(address artifact);
```

### NoBonusAvailable
No bonus available for the artifact with given multiplier.


```solidity
error NoBonusAvailable(address artifact, uint256 multiplier);
```

### NoRewardAvailable
No reward available for the artifact.


```solidity
error NoRewardAvailable(address artifact);
```

