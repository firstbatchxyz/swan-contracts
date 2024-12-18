# SwanAgentFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/24e0365940f0434545a9c39573dfdf6b9975fc88/src/SwanAgent.sol)

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

