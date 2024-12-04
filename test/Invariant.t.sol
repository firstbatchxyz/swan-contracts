// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Vm} from "forge-std/Vm.sol";
import {Helper} from "./Helper.t.sol";
import {SwanMarketParameters} from "../src/Swan.sol";

/// @notice Invariant tests call random functions from contracts and check the conditions inside the test
contract InvariantTest is Helper {
    // Owner is always an operator
    function invariant_OwnerIsAnOperator() public view {
        assertTrue(swan.isOperator(swan.owner()));
    }

    /// @dev Total number of assets listed does not exceed maxAssetCount
    function invariant_MaxAssetCount() public view {
        SwanMarketParameters memory params = swan.getCurrentMarketParameters();

        for (uint256 i = 0; i < buyerAgents.length; i++) {
            for (uint256 round = 0; round < 5; round++) {
                // asssuming a maximum of 5 rounds
                assertTrue(swan.getListedAssets(address(buyerAgents[i]), round).length <= params.maxAssetCount);
            }
        }
    }

    /// @dev Price of listed assets is within the acceptable range
    function invariant_AssetPriceRange() public view {
        SwanMarketParameters memory params = swan.getCurrentMarketParameters();

        for (uint256 i = 0; i < buyerAgents.length; i++) {
            for (uint256 round; round < 5; round++) {
                // assuming a maximum of 5 rounds
                address[] memory assets = swan.getListedAssets(address(buyerAgents[i]), round);
                for (uint256 j; j < assets.length; j++) {
                    uint256 price = swan.getListingPrice(assets[j]);
                    assertTrue(price >= params.minAssetPrice && price <= buyerAgents[i].amountPerRound());
                }
            }
        }
    }

    /// @dev Fee royalty of each buyer agent is within an acceptable range
    function invariant_BuyerAgentFeeRoyalty() public view {
        for (uint256 i = 0; i < buyerAgents.length; i++) {
            uint96 feeRoyalty = buyerAgents[i].feeRoyalty();
            assertTrue(feeRoyalty >= 0 && feeRoyalty <= 10000); // Assuming fee royalty is in basis points (0% to 100%)
        }
    }
}
