// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Swan} from "../src/Swan.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SwanManager, SwanMarketParameters} from "../src/SwanManager.sol";
import {LLMOracleTaskParameters} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {MockLLMOracleCoordinator} from "./mock/MockLLMOracleCoordinator.sol";
import {MockSwanAgentFactory} from "./mock/MockSwanAgentFactory.sol";
import {MockSwanArtifactFactory} from "./mock/MockSwanArtifactFactory.sol";

contract SwanUpgradeTest is Test {
    Swan swanImplementationV1;
    Swan proxy;

    MockERC20 token;
    MockLLMOracleCoordinator coordinator;
    MockSwanAgentFactory agentFactory;
    MockSwanArtifactFactory artifactFactory;

    address owner = address(0x1);
    address user = address(0x2);

    function setUp() public {
        // Deploy mock dependencies
        token = new MockERC20("Test Token", "TEST");
        coordinator = new MockLLMOracleCoordinator();
        agentFactory = new MockSwanAgentFactory();
        artifactFactory = new MockSwanArtifactFactory();

        vm.startPrank(owner);

        // Deploy the original implementation
        swanImplementationV1 = new Swan();

        SwanMarketParameters memory marketParams = SwanMarketParameters({
            withdrawInterval: 1 days,
            listingInterval: 2 days,
            buyInterval: 3 days,
            platformFee: 10,
            maxArtifactCount: 10,
            minArtifactPrice: 1 ether,
            timestamp: block.timestamp,
            maxAgentFee: 20
        });

        LLMOracleTaskParameters memory oracleParams =
            LLMOracleTaskParameters({difficulty: 1, numGenerations: 1, numValidations: 1});

        bytes memory initData = abi.encodeCall(
            Swan.initialize,
            (
                marketParams,
                oracleParams,
                address(coordinator),
                address(token),
                address(agentFactory),
                address(artifactFactory)
            )
        );

        // Deploy the proxy with the implementation and initialization data
        ERC1967Proxy proxyContract = new ERC1967Proxy(address(swanImplementationV1), initData);

        // Cast the proxy to Swan for easier interaction
        proxy = Swan(address(proxyContract));

        vm.stopPrank();

        // Verify initial setup
        assertEq(proxy.owner(), owner);
    }

    function testUpgrade() public {
        // Pre-upgrade checks
        assertEq(address(proxy.agentFactory()), address(agentFactory));
        assertEq(address(proxy.artifactFactory()), address(artifactFactory));

        // Deploy the new implementation
        vm.startPrank(owner);
        Swan swanImplementationV2 = new Swan();

        proxy.upgradeToAndCall(address(swanImplementationV2), "");
        vm.stopPrank();

        // Get implementation address
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 implementationValue = vm.load(address(proxy), implementationSlot);
        address currentImplementation = address(uint160(uint256(implementationValue)));

        assertEq(currentImplementation, address(swanImplementationV2));

        assertEq(address(proxy.agentFactory()), address(agentFactory));
        assertEq(address(proxy.artifactFactory()), address(artifactFactory));

        vm.startPrank(owner);
        address newAgentFactory = address(new MockSwanAgentFactory());
        address newArtifactFactory = address(new MockSwanArtifactFactory());
        proxy.setFactories(newAgentFactory, newArtifactFactory);
        vm.stopPrank();

        // Verify the new factories were set correctly
        assertEq(address(proxy.agentFactory()), newAgentFactory);
        assertEq(address(proxy.artifactFactory()), newArtifactFactory);
    }

    // Test that the upgrade fails if called by a non-owner
    function testUpgradeFailsWhenCalledByNonOwner() public {
        vm.startPrank(owner);
        Swan swanImplementationV2 = new Swan();
        vm.stopPrank();

        // Try to upgrade from a non-owner account
        vm.startPrank(user);
        vm.expectRevert();
        proxy.upgradeToAndCall(address(swanImplementationV2), "");
        vm.stopPrank();
    }
}
