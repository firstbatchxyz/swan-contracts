# ArtifactFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/c9444a397017d961972cbbff400b67d973ffe956/src/Artifact.sol)

Factory contract to deploy Artifact tokens.

*This saves from contract space for Swan.*


## Functions
### deploy

Deploys a new Artifact token.


```solidity
function deploy(string memory _name, string memory _symbol, bytes memory _description, address _owner)
    external
    returns (Artifact);
```

