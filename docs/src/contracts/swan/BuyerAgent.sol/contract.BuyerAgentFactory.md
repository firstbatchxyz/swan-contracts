# BuyerAgentFactory
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/ceefa4b0353ce4c0f1536b7318fa82b208305342/contracts/swan/BuyerAgent.sol)

Factory contract to deploy BuyerAgent contracts.

*This saves from contract space for Swan.*


## Functions
### deploy


```solidity
function deploy(
    string memory _name,
    string memory _description,
    uint96 _royaltyFee,
    uint256 _amountPerRound,
    address _owner
) external returns (BuyerAgent);
```

