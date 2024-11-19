// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Vm} from "../lib/forge-std/src/Vm.sol";
import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import {WETH9} from "../contracts/token/WETH9.sol";
import {LLMOracleRegistry, LLMOracleKind} from "../contracts/llm/LLMOracleRegistry.sol";
import {Helper} from "./Helper.t.sol";

contract LLMOracleRegistryTest is Helper {
    uint256 totalStakeAmount;
    address oracle;

    modifier deployment() {
        oracle = generators[0];
        totalStakeAmount = stakes.generatorStakeAmount + stakes.validatorStakeAmount;

        token = new WETH9();

        vm.startPrank(dria);
        address registryProxy = Upgrades.deployUUPSProxy(
            "LLMOracleRegistry.sol",
            abi.encodeCall(
                LLMOracleRegistry.initialize, (stakes.generatorStakeAmount, stakes.validatorStakeAmount, address(token))
            )
        );

        // wrap proxy with the LLMOracleRegistry contract to use in tests easily
        oracleRegistry = LLMOracleRegistry(registryProxy);
        vm.stopPrank();

        vm.label(oracle, "Oracle");
        vm.label(address(this), "LLMOracleRegistryTest");
        vm.label(address(oracleRegistry), "LLMOracleRegistry");
        vm.label(address(oracleCoordinator), "LLMOracleCoordinator");
        _;
    }

    /// @notice fund the oracle and dria
    modifier fund() {
        deal(address(token), dria, 1 ether);
        deal(address(token), oracle, totalStakeAmount);

        assertEq(token.balanceOf(dria), 1 ether);
        assertEq(token.balanceOf(oracle), totalStakeAmount);
        _;
    }

    // move to helper ?
    modifier registerOracle(LLMOracleKind kind) {
        // register oracle
        vm.startPrank(oracle);
        token.approve(address(oracleRegistry), totalStakeAmount);

        // Register the generator oracle
        oracleRegistry.register(kind);
        vm.stopPrank();
        _;
    }

    // move to helper ?
    modifier unregisterOracle(LLMOracleKind kind) {
        // Simulate the oracle account
        vm.startPrank(oracle);
        token.approve(address(oracleRegistry), stakes.generatorStakeAmount);
        oracleRegistry.unregister(kind);
        vm.stopPrank();

        assertFalse(oracleRegistry.isRegistered(oracle, LLMOracleKind.Generator));
        _;
    }

    function test_Deployment() external deployment {
        assertEq(oracleRegistry.generatorStakeAmount(), stakes.generatorStakeAmount);
        assertEq(oracleRegistry.validatorStakeAmount(), stakes.validatorStakeAmount);

        assertEq(address(oracleRegistry.token()), address(token));
        assertEq(oracleRegistry.owner(), dria);
    }

    /// @notice Registry has not approved by oracle
    function test_RevertWhen_RegistryHasNotApprovedByOracle() external deployment {
        // oracle has the funds but has not approved yet
        deal(address(token), oracle, totalStakeAmount);

        vm.expectRevert(abi.encodeWithSelector(LLMOracleRegistry.InsufficientFunds.selector));
        oracleRegistry.register(LLMOracleKind.Generator);
    }

    /// @notice Oracle has enough funds and approve registry
    function test_RegisterGeneratorOracle() external deployment fund registerOracle(LLMOracleKind.Generator) {}

    /// @notice Same oracle try to register twice
    function test_RevertWhen_RegisterSameGeneratorTwice()
        external
        deployment
        fund
        registerOracle(LLMOracleKind.Generator)
    {
        vm.prank(oracle);
        vm.expectRevert(abi.encodeWithSelector(LLMOracleRegistry.AlreadyRegistered.selector, oracle));

        oracleRegistry.register(LLMOracleKind.Generator);
    }

    /// @notice Oracle registers as validator
    function test_RegisterValidatorOracle() external deployment fund registerOracle(LLMOracleKind.Validator) {}

    /// @notice Oracle unregisters as generator
    function test_UnregisterOracle()
        external
        deployment
        fund
        registerOracle(LLMOracleKind.Generator)
        unregisterOracle(LLMOracleKind.Generator)
    {}

    /// @notice Oracle try to unregisters as generator twice
    function test_RevertWhen_UnregisterSameGeneratorTwice()
        external
        deployment
        fund
        registerOracle(LLMOracleKind.Generator)
        unregisterOracle(LLMOracleKind.Generator)
    {
        vm.prank(oracle);
        vm.expectRevert(abi.encodeWithSelector(LLMOracleRegistry.NotRegistered.selector, oracle));
        oracleRegistry.unregister(LLMOracleKind.Generator);
    }

    /// @notice Oracle can withdraw stakes after unregistering
    /// @dev 1. Register as generator
    /// @dev 2. Register as validator
    /// @dev 3. Unregister as generator
    /// @dev 4. Unregister as validator
    /// @dev 5. withdraw stakes
    function test_WithdrawStakesAfterUnregistering()
        external
        deployment
        fund
        registerOracle(LLMOracleKind.Generator)
        registerOracle(LLMOracleKind.Validator)
        unregisterOracle(LLMOracleKind.Generator)
        unregisterOracle(LLMOracleKind.Validator)
    {
        uint256 balanceBefore = token.balanceOf(oracle);
        token.approve(address(oracleRegistry), totalStakeAmount);

        // withdraw stakes
        vm.startPrank(oracle);
        token.transferFrom(address(oracleRegistry), oracle, (totalStakeAmount));

        uint256 balanceAfter = token.balanceOf(oracle);
        assertEq(balanceAfter - balanceBefore, totalStakeAmount);
    }
}
