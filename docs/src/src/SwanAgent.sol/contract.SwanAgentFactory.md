# SwanAgentFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/d7951743b0ff97c2f6e978aeabb850c0310d76f3/src/SwanAgent.sol)

Factory contract to deploy Agent contracts.

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
) external returns (SwanAgent);
```

