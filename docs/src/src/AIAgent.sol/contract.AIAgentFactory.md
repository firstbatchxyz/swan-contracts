# AIAgentFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/feb8dd64d672a341a29a0a52b12cc56adf09c996/src/AIAgent.sol)

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

