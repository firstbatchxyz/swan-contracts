# AIAgentFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/6a4c427284ef9a1b566dad7645b1c42a55dd3690/src/AIAgent.sol)

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

