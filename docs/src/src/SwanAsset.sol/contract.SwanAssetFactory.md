# SwanAssetFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/9405ff2bcd559928c6612c334c22d32bfecae969/src/SwanAsset.sol)

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

