# SwanAssetFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/b941dcd71134f5be2e73ec6ee0a8aa50cf333ffb/src/SwanAsset.sol)

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

