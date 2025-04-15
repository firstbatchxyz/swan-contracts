// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SwanArtifactFactory, SwanArtifact} from "../../src/SwanArtifact.sol";

contract MockSwanArtifactFactory {
    function deploy(string calldata _name, string calldata _symbol, bytes calldata _desc, address _owner)
        external
        returns (SwanArtifact)
    {
        // Return a mock artifact
        return SwanArtifact(address(0));
    }
}
