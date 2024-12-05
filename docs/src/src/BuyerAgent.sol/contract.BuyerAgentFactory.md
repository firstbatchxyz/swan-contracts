# BuyerAgentFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/170a81d7fdcb6e8e1e1df26e3a5bd45ec4316d4a/src/BuyerAgent.sol)

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

