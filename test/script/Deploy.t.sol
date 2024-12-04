// SPDX-License-Identifier: Apache-2.0

import {Deploy} from "../../script/Deploy.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {LLMOracleRegistry} from "@firstbatch/dria-oracle-contracts/LLMOracleRegistry.sol";
import {LLMOracleCoordinator} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";
import {Swan} from "../../src/Swan.sol";

pragma solidity ^0.8.20;

contract DeployTest is Test {
    Deploy deployer;

    LLMOracleCoordinator coordinator;
    LLMOracleRegistry registry;
    Swan swan;

    function setUp() external {
        deployer = new Deploy();
        deployer.run();
    }

    modifier deployed() {
        registry = deployer.oracleRegistry();
        coordinator = deployer.oracleCoordinator();
        swan = deployer.swan();

        assert(address(registry) != address(0));
        assert(address(swan) != address(0));
        assert(address(coordinator) != address(0));

        assert(coordinator.registry() == registry);
        assert(swan.coordinator() == coordinator);
        _;
    }

    function test_Deploy() external deployed {}
}
