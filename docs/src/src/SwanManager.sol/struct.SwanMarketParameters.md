# SwanMarketParameters
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/d7951743b0ff97c2f6e978aeabb850c0310d76f3/src/SwanManager.sol)

Collection of market-related parameters.

*Prevents stack-too-deep.*


```solidity
struct SwanMarketParameters {
    uint256 withdrawInterval;
    uint256 listingInterval;
    uint256 buyInterval;
    uint256 platformFee;
    uint256 maxArtifactCount;
    uint256 minArtifactPrice;
    uint256 timestamp;
    uint8 maxAgentFee;
}
```

