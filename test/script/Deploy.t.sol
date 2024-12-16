// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {
    DeployAIAgentFactory,
    DeployArtifactFactory,
    DeployLLMOracleCoordinator,
    DeployLLMOracleRegistry,
    DeploySwan
} from "../../script/Deploy.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {LLMOracleRegistry} from "@firstbatch/dria-oracle-contracts/LLMOracleRegistry.sol";
import {LLMOracleCoordinator} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";
import {Swan} from "../../src/Swan.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";

contract DeployTest is Test {
    DeployAIAgentFactory deployAgentFactory;
    DeployArtifactFactory deployArtifactFactory;
    DeployLLMOracleCoordinator deployLLMOracleCoordinator;
    DeployLLMOracleRegistry deployLLMOracleRegistry;
    DeploySwan deploySwan;

    address swanProxy;
    address swanImpl;

    address agentFactory;
    address artifactFactory;

    address llmOracleCoordinatorProxy;
    address llmOracleCoordinatorImpl;

    address llmOracleRegistryProxy;
    address llmOracleRegistryImpl;

    function setUp() external {
        deployAgentFactory = new DeployAIAgentFactory();
        agentFactory = deployAgentFactory.run();

        deployArtifactFactory = new DeployArtifactFactory();
        artifactFactory = deployArtifactFactory.run();

        deployLLMOracleRegistry = new DeployLLMOracleRegistry();
        (llmOracleRegistryProxy, llmOracleRegistryImpl) = deployLLMOracleRegistry.run();

        deployLLMOracleCoordinator = new DeployLLMOracleCoordinator();
        (llmOracleCoordinatorProxy, llmOracleCoordinatorImpl) = deployLLMOracleCoordinator.run();

        deploySwan = new DeploySwan();
        (swanProxy, swanImpl) = deploySwan.run();
    }

    modifier deployed() {
        // check deployed addresses are not zero
        require(agentFactory != address(0), "AgentFactory not deployed");
        require(artifactFactory != address(0), "ArtifactFactory not deployed");

        require(llmOracleRegistryProxy != address(0), "LLMOracleRegistry not deployed");
        require(llmOracleRegistryImpl != address(0), "LLMOracleRegistry implementation not deployed");

        require(llmOracleCoordinatorProxy != address(0), "LLMOracleCoordinator not deployed");
        require(llmOracleCoordinatorImpl != address(0), "LLMOracleCoordinator implementation not deployed");

        require(swanProxy != address(0), "Swan not deployed");
        require(swanImpl != address(0), "Swan implementation not deployed");

        // check if implementations are correct
        address expectedRegistryImpl = Upgrades.getImplementationAddress(llmOracleRegistryProxy);
        address expectedCoordinatorImpl = Upgrades.getImplementationAddress(llmOracleCoordinatorProxy);
        address expectedSwanImpl = Upgrades.getImplementationAddress(swanProxy);

        require(llmOracleRegistryImpl == expectedRegistryImpl, "LLMOracleRegistry implementation mismatch");
        require(llmOracleCoordinatorImpl == expectedCoordinatorImpl, "LLMOracleCoordinator implementation mismatch");
        require(swanImpl == expectedSwanImpl, "Swan implementation mismatch");
        _;
    }

    function test_Deploy() external deployed {}
}
