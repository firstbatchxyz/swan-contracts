# SwanArtifact
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/d9d9060075900e963ed93f2465a5d30c142fcc35/src/SwanArtifact.sol)

**Inherits:**
ERC721, Ownable

Artifact is an ERC721 token with a single token supply.


## State Variables
### createdAt
Creation time of the token


```solidity
uint256 public createdAt;
```


### description
Description of the token


```solidity
bytes public description;
```


## Functions
### constructor

Constructor sets properties of the token.


```solidity
constructor(string memory _name, string memory _symbol, bytes memory _description, address _owner, address _operator)
    ERC721(_name, _symbol)
    Ownable(_owner);
```
