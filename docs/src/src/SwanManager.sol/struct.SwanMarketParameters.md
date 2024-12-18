# SwanMarketParameters
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/d9d9060075900e963ed93f2465a5d30c142fcc35/src/SwanManager.sol)

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

