// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Script} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

import {LLMOracleRegistry} from "@firstbatch/dria-oracle-contracts/LLMOracleRegistry.sol";
import {
    LLMOracleCoordinator, LLMOracleTaskParameters
} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";
import {SwanAgentFactory} from "../src/SwanAgent.sol";
import {SwanArtifactFactory} from "../src/SwanArtifact.sol";
import {Swan, SwanMarketParameters} from "../src/Swan.sol";

// needed for tests
contract DeployLLMOracleRegistry is Script {
    HelperConfig public config;

    function run() external returns (address proxy, address impl) {
        config = new HelperConfig();
        (proxy, impl) = config.deployLLMOracleRegistry();
    }
}

// needed for tests
contract DeployLLMOracleCoordinator is Script {
    HelperConfig public config;

    function run() external returns (address proxy, address impl) {
        config = new HelperConfig();
        (proxy, impl) = config.deployLLMOracleCoordinator();
    }
}

contract DeploySwanAgentFactory is Script {
    HelperConfig public config;

    function run() external returns (address addr) {
        config = new HelperConfig();
        addr = config.deployAgentFactory();
    }
}

contract DeploySwanArtifactFactory is Script {
    HelperConfig public config;

    function run() external returns (address addr) {
        config = new HelperConfig();
        addr = config.deployArtifactFactory();
    }
}

contract DeploySwan is Script {
    HelperConfig public config;

    function run() external returns (address proxy, address impl) {
        config = new HelperConfig();
        (proxy, impl) = config.deploySwan();
    }
}

contract DeploySwanImpl is Script {
    HelperConfig public config;

    function run() external returns (address addr) {
        config = new HelperConfig();
        addr = config.deploySwanImpl();
    }
}

contract DeploySwanLottery is Script {
    HelperConfig public config;

    function run() external returns (address addr) {
        config = new HelperConfig();
        addr = config.deploySwanLottery();
    }
}

contract DeploySwanDebate is Script {
    HelperConfig public config;

    function run() external returns (address addr) {
        config = new HelperConfig();
        addr = config.deploySwanDebate();
    }
}
