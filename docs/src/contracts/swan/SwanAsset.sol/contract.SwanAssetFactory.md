# SwanAssetFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/ceefa4b0353ce4c0f1536b7318fa82b208305342/contracts/swan/SwanAsset.sol)

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

