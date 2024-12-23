# SwanMarketParameters
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/cfde01cea84285a32250228f5358ebebeb0fc85a/src/SwanManager.sol)

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

