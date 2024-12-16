# ArtifactFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/feb8dd64d672a341a29a0a52b12cc56adf09c996/src/Artifact.sol)

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

