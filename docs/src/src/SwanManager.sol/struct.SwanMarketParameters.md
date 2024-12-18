# SwanMarketParameters
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/24e0365940f0434545a9c39573dfdf6b9975fc88/src/SwanManager.sol)

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

