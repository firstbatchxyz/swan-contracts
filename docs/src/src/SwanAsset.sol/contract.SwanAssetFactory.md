# SwanAssetFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/71d5f1b72c5506ee91313ea31c9a617e611d9d74/src/SwanAsset.sol)

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

