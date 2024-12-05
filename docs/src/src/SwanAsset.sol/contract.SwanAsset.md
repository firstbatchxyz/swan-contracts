# SwanAsset
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/9405ff2bcd559928c6612c334c22d32bfecae969/src/SwanAsset.sol)

**Inherits:**
ERC721, Ownable

SwanAsset is an ERC721 token with a single token supply.


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

