// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Swan} from "../../src/Swan.sol";

/// @notice Mock contract to simulate an upgrade.
contract SwanV2 is Swan {
    function upgraded() public view virtual returns (bool) {
        return true;
    }
}
