# SwanArtifactFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/d9d9060075900e963ed93f2465a5d30c142fcc35/src/SwanArtifact.sol)

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

