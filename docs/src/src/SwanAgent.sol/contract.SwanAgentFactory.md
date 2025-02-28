# SwanAgentFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/c710fa9077819fe0de37f142a56e70d195d44ae7/src/SwanAgent.sol)

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

