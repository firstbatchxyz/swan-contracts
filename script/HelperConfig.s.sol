// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Script} from "../lib/forge-std/src/Script.sol";
import {WETH9} from "../contracts/token/WETH9.sol";
import {LLMOracleTaskParameters} from "../contracts/llm/LLMOracleTask.sol";
import {SwanMarketParameters} from "../contracts/swan/SwanManager.sol";

struct Stakes {
    uint256 generatorStakeAmount;
    uint256 validatorStakeAmount;
}

struct Fees {
    uint256 platformFee;
    uint256 generatorFee;
    uint256 validatorFee;
}

contract HelperConfig is Script {
    LLMOracleTaskParameters public taskParams;
    SwanMarketParameters public marketParams;

    Stakes public stakes;
    Fees public fees;
    WETH9 public token;

    // local key
    uint256 public constant ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        // set deployment parameters
        stakes = Stakes({generatorStakeAmount: 0.0001 ether, validatorStakeAmount: 0.000001 ether});
        fees = Fees({platformFee: 0.0001 ether, generatorFee: 0.0001 ether, validatorFee: 0.0001 ether});
        taskParams = LLMOracleTaskParameters({difficulty: 2, numGenerations: 1, numValidations: 1});

        marketParams = SwanMarketParameters({
            maxAssetCount: 500,
            sellInterval: 4 hours,
            buyInterval: 30 minutes,
            withdrawInterval: 15 minutes,
            platformFee: 1, // percentage
            minAssetPrice: 0.00001 ether,
            timestamp: 0 // will be set in the first call
        });

        // for base sepolia
        if (block.chainid == 84532) {
            // use deployed weth
            token = WETH9(payable(0x4200000000000000000000000000000000000006));
        }
        // for local create a new token
        token = new WETH9();
    }
}
