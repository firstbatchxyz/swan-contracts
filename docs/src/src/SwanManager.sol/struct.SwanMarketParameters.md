# SwanMarketParameters
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/feb8dd64d672a341a29a0a52b12cc56adf09c996/src/SwanManager.sol)

Collection of market-related parameters.

*Prevents stack-too-deep.
TODO: use 256-bit tight-packing here*


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

