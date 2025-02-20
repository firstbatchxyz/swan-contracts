// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {LLMOracleTaskParameters} from "@firstbatch/dria-oracle-contracts/LLMOracleTask.sol";

contract MockOracle {
    uint256 public nextTaskId = 1;

    function request(
        bytes32 protocol,
        bytes calldata input,
        bytes calldata models,
        LLMOracleTaskParameters calldata oracleParameters
    ) external returns (uint256) {
        return nextTaskId++;
    }
}
