# BuyerAgentFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/9405ff2bcd559928c6612c334c22d32bfecae969/src/BuyerAgent.sol)

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

