# SwanAgentFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/cfde01cea84285a32250228f5358ebebeb0fc85a/src/SwanAgent.sol)

Factory contract to deploy Agent contracts.

*This saves from contract space for Swan.*


## Functions
### deploy


```solidity
function deploy(
    string memory _name,
    string memory _description,
    uint96 _listingFee,
    uint256 _amountPerRound,
    address _owner
) external returns (SwanAgent);
```

