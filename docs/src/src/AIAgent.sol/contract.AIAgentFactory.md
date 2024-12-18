# AIAgentFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/c9444a397017d961972cbbff400b67d973ffe956/src/AIAgent.sol)

Factory contract to deploy AIAgent contracts.

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
) external returns (AIAgent);
```

