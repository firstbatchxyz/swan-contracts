# SwanArtifactFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/24e0365940f0434545a9c39573dfdf6b9975fc88/src/SwanArtifact.sol)

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

