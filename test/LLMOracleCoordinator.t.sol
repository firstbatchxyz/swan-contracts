// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {LLMOracleTask, LLMOracleTaskParameters} from "../contracts/llm/LLMOracleTask.sol";
import {LLMOracleRegistry, LLMOracleKind} from "../contracts/llm/LLMOracleRegistry.sol";
import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import {LLMOracleCoordinator} from "../contracts/llm/LLMOracleCoordinator.sol";
import {WETH9} from "../contracts/token/WETH9.sol";
import {Vm} from "../lib/forge-std/src/Vm.sol";
import {Helper} from "./Helper.t.sol";

contract LLMOracleCoordinatorTest is Helper {
    address dummy = vm.addr(20);
    address requester = vm.addr(21);

    bytes output = "0x";

    modifier deployment() {
        vm.startPrank(dria);
        address registryProxy = Upgrades.deployUUPSProxy(
            "LLMOracleRegistry.sol",
            abi.encodeCall(
                LLMOracleRegistry.initialize, (stakes.generatorStakeAmount, stakes.validatorStakeAmount, address(token))
            )
        );

        // wrap proxy with the LLMOracleRegistry contract to use in tests easily
        oracleRegistry = LLMOracleRegistry(registryProxy);

        // deploy coordinator contract
        address coordinatorProxy = Upgrades.deployUUPSProxy(
            "LLMOracleCoordinator.sol",
            abi.encodeCall(
                LLMOracleCoordinator.initialize,
                (address(oracleRegistry), address(token), fees.platformFee, fees.generationFee, fees.validationFee)
            )
        );
        oracleCoordinator = LLMOracleCoordinator(coordinatorProxy);
        vm.stopPrank();

        vm.label(dummy, "Dummy");
        vm.label(requester, "Requester");
        vm.label(address(this), "LLMOracleCoordinatorTest");
        vm.label(address(oracleRegistry), "LLMOracleRegistry");
        vm.label(address(oracleCoordinator), "LLMOracleCoordinator");
        _;
    }

    modifier fund() {
        // deploy weth
        token = new WETH9();

        // fund dria & requester
        deal(address(token), dria, 1 ether);
        deal(address(token), requester, 1 ether);

        // fund generators and validators
        for (uint256 i = 0; i < generators.length; i++) {
            deal(address(token), generators[i], stakes.generatorStakeAmount + stakes.validatorStakeAmount);
            assertEq(token.balanceOf(generators[i]), stakes.generatorStakeAmount + stakes.validatorStakeAmount);
        }
        for (uint256 i = 0; i < validators.length; i++) {
            deal(address(token), validators[i], stakes.validatorStakeAmount);
            assertEq(token.balanceOf(validators[i]), stakes.validatorStakeAmount);
        }
        _;
    }

    function test_Deployment() external fund deployment {
        assertEq(oracleRegistry.generatorStakeAmount(), stakes.generatorStakeAmount);
        assertEq(oracleRegistry.validatorStakeAmount(), stakes.validatorStakeAmount);

        assertEq(address(oracleRegistry.token()), address(token));
        assertEq(oracleRegistry.owner(), dria);

        // check the coordinator variables
        assertEq(address(oracleCoordinator.feeToken()), address(token));
        assertEq(address(oracleCoordinator.registry()), address(oracleRegistry));
        assertEq(oracleCoordinator.platformFee(), fees.platformFee);
        assertEq(oracleCoordinator.generationFee(), fees.generationFee);
        assertEq(oracleCoordinator.validationFee(), fees.validationFee);
    }

    /// @notice Test the registerOracles modifier to check if the oracles are registered
    function test_RegisterOracles() external fund deployment registerOracles {
        for (uint256 i; i < generators.length; i++) {
            assertTrue(oracleRegistry.isRegistered(generators[i], LLMOracleKind.Generator));
        }

        for (uint256 i; i < validators.length; i++) {
            assertTrue(oracleRegistry.isRegistered(validators[i], LLMOracleKind.Validator));
        }
    }

    // @notice Test without validation
    function test_WithoutValidation()
        external
        fund
        setOracleParameters(1, 2, 0)
        deployment
        registerOracles
        safeRequest(requester, 1)
        checkAllowances
    {
        uint256 responseId;

        // try to respond as an outsider (should fail)
        uint256 dummyNonce = mineNonce(dummy, 1);
        vm.expectRevert(abi.encodeWithSelector(LLMOracleRegistry.NotRegistered.selector, dummy));
        vm.prank(dummy);
        oracleCoordinator.respond(1, dummyNonce, output, metadata);

        // respond as the first generator
        safeRespond(generators[0], output, 1);

        // verify the response
        (address _responder,,, bytes memory _output,) = oracleCoordinator.responses(1, responseId);
        assertEq(_responder, generators[0]);
        assertEq(output, _output);
        responseId++;

        // try responding again (should fail)
        uint256 genNonce0 = mineNonce(generators[0], 1);
        vm.expectRevert(abi.encodeWithSelector(LLMOracleCoordinator.AlreadyResponded.selector, 1, generators[0]));
        vm.prank(generators[0]);
        oracleCoordinator.respond(1, genNonce0, output, metadata);

        // second responder responds
        safeRespond(generators[1], output, 1);
        responseId++;

        // try to respond after task completion (should fail)
        uint256 genNonce1 = mineNonce(generators[1], 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                LLMOracleCoordinator.InvalidTaskStatus.selector,
                1,
                uint8(LLMOracleTask.TaskStatus.Completed),
                uint8(LLMOracleTask.TaskStatus.PendingGeneration)
            )
        );
        vm.prank(generators[1]);
        oracleCoordinator.respond(1, genNonce1, output, metadata);

        // try to respond to a non-existent task (should fail)
        vm.expectRevert(
            abi.encodeWithSelector(
                LLMOracleCoordinator.InvalidTaskStatus.selector,
                900,
                uint8(LLMOracleTask.TaskStatus.None),
                uint8(LLMOracleTask.TaskStatus.PendingGeneration)
            )
        );
        vm.prank(generators[0]);
        oracleCoordinator.respond(900, genNonce0, output, metadata);
    }

    // @notice Test with single validation
    function test_WithValidation()
        external
        fund
        setOracleParameters(1, 2, 2)
        deployment
        registerOracles
        safeRequest(requester, 1)
        checkAllowances
    {
        // generators respond
        for (uint256 i = 0; i < oracleParameters.numGenerations; i++) {
            safeRespond(generators[i], output, 1);
        }

        // set scores
        scores = [1 ether, 1 ether];

        uint256 genNonce = mineNonce(generators[2], 1);
        // ensure third generator can't respond after completion
        vm.expectRevert(
            abi.encodeWithSelector(
                LLMOracleCoordinator.InvalidTaskStatus.selector,
                1,
                uint8(LLMOracleTask.TaskStatus.PendingValidation),
                uint8(LLMOracleTask.TaskStatus.PendingGeneration)
            )
        );
        vm.prank(generators[2]);
        oracleCoordinator.respond(1, genNonce, output, metadata);

        // validator validate
        safeValidate(validators[0], 1);

        uint256 valNonce = mineNonce(validators[0], 1);
        // ensure first validator can't validate twice
        vm.expectRevert(abi.encodeWithSelector(LLMOracleCoordinator.AlreadyResponded.selector, 1, validators[0]));
        vm.prank(validators[0]);
        oracleCoordinator.validate(1, valNonce, scores, metadata);

        // second validator validates and completes the task
        safeValidate(validators[1], 1);

        // check the task's status is Completed
        (,,, LLMOracleTask.TaskStatus status,,,,,) = oracleCoordinator.requests(1);
        assertEq(uint8(status), uint8(LLMOracleTask.TaskStatus.Completed));

        // should see generation scores
        for (uint256 i = 0; i < oracleParameters.numGenerations; i++) {
            (,, uint256 responseScore,,) = oracleCoordinator.responses(1, i);
            assertEq(responseScore, 1 ether);
        }
    }

    /// @dev Oracle cannot validate if already participated as generator
    function test_ValidatorIsGenerator()
        external
        fund
        setOracleParameters(1, 1, 1)
        deployment
        registerOracles
        safeRequest(requester, 1)
    {
        // register generators[0] as a validator as well
        vm.prank(generators[0]);
        oracleRegistry.register(LLMOracleKind.Validator);

        // respond as generator
        for (uint256 i = 0; i < oracleParameters.numGenerations; i++) {
            safeRespond(generators[i], output, 1);
        }

        // set scores for (setOracleParameters(1, 1, 1))
        scores = [1 ether];

        // try to validate after responding as generator
        uint256 nonce = mineNonce(generators[0], 1);
        vm.prank(generators[0]);
        vm.expectRevert(abi.encodeWithSelector(LLMOracleCoordinator.AlreadyResponded.selector, 1, generators[0]));
        oracleCoordinator.validate(1, nonce, scores, metadata);
    }
}
