# BuyerAgentFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/b941dcd71134f5be2e73ec6ee0a8aa50cf333ffb/src/BuyerAgent.sol)

Factory contract to deploy BuyerAgent contracts.

*This saves from contract space for Swan.*


## Functions
### deploy


```solidity
function deploy(
    string memory _name,
    string memory _description,
    uint96 _feeRoyalty,
    uint256 _amountPerRound,
    address _owner
) external returns (BuyerAgent);
```

