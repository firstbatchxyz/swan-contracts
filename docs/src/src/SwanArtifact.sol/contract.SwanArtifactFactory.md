# SwanArtifactFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/cfde01cea84285a32250228f5358ebebeb0fc85a/src/SwanArtifact.sol)

Factory contract to deploy Artifact tokens.

*This saves from contract space for Swan.*


## Functions
### deploy

Deploys a new Artifact token.


```solidity
function deploy(string memory _name, string memory _symbol, bytes memory _description, address _owner)
    external
    returns (SwanArtifact);
```

