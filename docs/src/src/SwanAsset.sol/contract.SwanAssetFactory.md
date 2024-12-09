# SwanAssetFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/170a81d7fdcb6e8e1e1df26e3a5bd45ec4316d4a/src/SwanAsset.sol)

Factory contract to deploy SwanAsset tokens.

*This saves from contract space for Swan.*


## Functions
### deploy

Deploys a new SwanAsset token.


```solidity
function deploy(string memory _name, string memory _symbol, bytes memory _description, address _owner)
    external
    returns (SwanAsset);
```

