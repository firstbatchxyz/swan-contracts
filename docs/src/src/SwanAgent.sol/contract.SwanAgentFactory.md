# SwanAgentFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/d9d9060075900e963ed93f2465a5d30c142fcc35/src/SwanAgent.sol)

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

