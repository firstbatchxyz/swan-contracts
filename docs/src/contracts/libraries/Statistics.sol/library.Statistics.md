# Statistics
[Git Source](https://github.com/firstbatchxyz/swan-contracts/blob/ceefa4b0353ce4c0f1536b7318fa82b208305342/contracts/libraries/Statistics.sol)

Simple statistic library for uint256 arrays, numbers are treat as fixed-precision floats.


## Functions
### avg

Compute the mean of the data.


```solidity
function avg(uint256[] memory data) internal pure returns (uint256 ans);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`uint256[]`|The data to compute the mean for.|


### variance

Compute the variance of the data.


```solidity
function variance(uint256[] memory data) internal pure returns (uint256 ans, uint256 mean);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`uint256[]`|The data to compute the variance for.|


### stddev

Compute the standard deviation of the data.

*Computes variance, and takes the square root.*


```solidity
function stddev(uint256[] memory data) internal pure returns (uint256 ans, uint256 mean);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`data`|`uint256[]`|The data to compute the standard deviation for.|


### sqrt

Compute the square root of a number.

*Uses Babylonian method.*


```solidity
function sqrt(uint256 x) internal pure returns (uint256 y);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`x`|`uint256`|The number to compute the square root for.|


