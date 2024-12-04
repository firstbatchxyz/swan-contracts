# BuyerAgentFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/71d5f1b72c5506ee91313ea31c9a617e611d9d74/src/BuyerAgent.sol)

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

