// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Vm} from "forge-std/Vm.sol";
import {Helper} from "./Helper.t.sol";
import {SwanMarketParameters} from "../src/Swan.sol";

/// @notice Invariant tests call random functions from contracts and check the conditions inside the test
contract InvariantTest is Helper {
    /// @dev Owner is always an operator
    function invariant_OwnerIsAnOperator() public view {
        assertTrue(swan.isOperator(swan.owner()));
    }

    /// @dev Total number of artifacts listed does not exceed maxArtifactCount
    function invariant_MaxArtifactCount() public view {
        SwanMarketParameters memory params = swan.getCurrentMarketParameters();

        for (uint256 i = 0; i < agents.length; i++) {
            for (uint256 round = 0; round < 5; round++) {
                // asssuming a maximum of 5 rounds
                assertTrue(swan.getListedArtifacts(address(agents[i]), round).length <= params.maxArtifactCount);
            }
        }
    }

    /// @dev Price of listed artifacts is within the acceptable range
    function invariant_ArtifactPriceRange() public view {
        SwanMarketParameters memory _params = swan.getCurrentMarketParameters();

        for (uint256 i = 0; i < agents.length; i++) {
            for (uint256 round; round < 5; round++) {
                // assuming a maximum of 5 rounds
                address[] memory artifacts = swan.getListedArtifacts(address(agents[i]), round);
                for (uint256 j; j < artifacts.length; j++) {
                    uint256 price = swan.getListingPrice(artifacts[j]);
                    assertTrue(price >= _params.minArtifactPrice && price <= agents[i].amountPerRound());
                }
            }
        }
    }

    /// @dev Fee royalty of each agent is within an acceptable range
    function invariant_AgentFeeRoyalty() public view {
        for (uint256 i = 0; i < agents.length; i++) {
            uint96 _feeRoyalty = agents[i].feeRoyalty();
            assertTrue(_feeRoyalty >= 0 && _feeRoyalty <= 10000); // Assuming fee royalty is in basis points (0% to 100%)
        }
    }
}
