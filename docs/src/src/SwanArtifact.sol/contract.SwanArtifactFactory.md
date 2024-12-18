# SwanArtifactFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/d7951743b0ff97c2f6e978aeabb850c0310d76f3/src/SwanArtifact.sol)

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

