// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {WETH9} from "../test/WETH9.sol";
import {LLMOracleTaskParameters} from "@firstbatch/dria-oracle-contracts/LLMOracleTask.sol";
import {SwanMarketParameters} from "../src/SwanManager.sol";

struct Stakes {
    uint256 generatorStakeAmount;
    uint256 validatorStakeAmount;
}

struct Fees {
    uint256 platformFee;
    uint256 generationFee;
    uint256 validationFee;
}

contract HelperConfig is Script {
    LLMOracleTaskParameters public taskParams;
    SwanMarketParameters public marketParams;

    Stakes public stakes;
    Fees public fees;
    WETH9 public token;

    uint256 public minRegistrationTime; // in seconds
    uint256 public minScore;
    uint256 public maxScore;

    constructor() {
        // set deployment parameters
        stakes = Stakes({generatorStakeAmount: 0.0001 ether, validatorStakeAmount: 0.000001 ether});
        fees = Fees({platformFee: 0.0001 ether, generationFee: 0.0001 ether, validationFee: 0.0001 ether});
        taskParams = LLMOracleTaskParameters({difficulty: 2, numGenerations: 1, numValidations: 1});

        marketParams = SwanMarketParameters({
            maxAssetCount: 500,
            sellInterval: 4 hours,
            buyInterval: 30 minutes,
            withdrawInterval: 15 minutes,
            platformFee: 1, // percentage
            minAssetPrice: 0.00001 ether,
            timestamp: 0, // will be set in the first call
            maxBuyerAgentFee: 75 // percentage
        });

        minRegistrationTime = 1 days;
        maxScore = type(uint8).max; // 255
        minScore = 1;

        // for base sepolia
        if (block.chainid == 84532 || block.chainid == 8453) {
            // use deployed weth
            token = WETH9(payable(0x4200000000000000000000000000000000000006));
        }
        // for local create a new token
        token = new WETH9();
    }
}
