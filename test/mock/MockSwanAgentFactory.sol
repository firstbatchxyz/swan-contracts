// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SwanAgentFactory, SwanAgent} from "../../src/SwanAgent.sol";

contract MockSwanAgentFactory {
    function deploy(
        string calldata _name,
        string calldata _description,
        uint96 _listingFee,
        uint256 _amountPerRound,
        address _owner
    ) external returns (SwanAgent) {
        // Return a mock agent
        return SwanAgent(address(0));
    }
}
