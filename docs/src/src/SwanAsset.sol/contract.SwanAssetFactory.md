# SwanAssetFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/6a4c427284ef9a1b566dad7645b1c42a55dd3690/src/SwanAsset.sol)

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

