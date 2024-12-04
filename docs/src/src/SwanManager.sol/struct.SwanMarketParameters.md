# SwanMarketParameters
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/71d5f1b72c5506ee91313ea31c9a617e611d9d74/src/SwanManager.sol)

Collection of market-related parameters.

*Prevents stack-too-deep.
TODO: use 256-bit tight-packing here*


```solidity
struct SwanMarketParameters {
    uint256 withdrawInterval;
    uint256 sellInterval;
    uint256 buyInterval;
    uint256 platformFee;
    uint256 maxAssetCount;
    uint256 minAssetPrice;
    uint256 timestamp;
    uint8 maxBuyerAgentFee;
}
```

