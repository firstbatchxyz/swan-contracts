# SwanMarketParameters
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/ceefa4b0353ce4c0f1536b7318fa82b208305342/contracts/swan/SwanManager.sol)

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
}
```

