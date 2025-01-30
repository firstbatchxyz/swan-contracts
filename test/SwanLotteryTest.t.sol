// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Helper} from "./Helper.t.sol";
import {SwanLottery} from "../src/SwanLottery.sol";
import {SwanAgent} from "../src/SwanAgent.sol";
import {SwanArtifact} from "../src/SwanArtifact.sol";
import {Swan} from "../src/Swan.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Vm} from "forge-std/Vm.sol";
import {LLMOracleTask, LLMOracleTaskParameters} from "@firstbatch/dria-oracle-contracts/LLMOracleTask.sol";
import {LLMOracleKind} from "@firstbatch/dria-oracle-contracts/LLMOracleRegistry.sol";

contract SwanLotteryTest is Helper {
    uint256 public constant BASIS_POINTS = 10000;
    bytes public constant TEST_OUTPUT = "test output";

    /// @dev Fund wallets for testing
    modifier fund() {
        // fund platform
        deal(address(token), dria, 1 ether);

        // fund sellers
        for (uint256 i; i < sellers.length; i++) {
            deal(address(token), sellers[i], 5 ether);
            assertEq(token.balanceOf(sellers[i]), 5 ether);
            vm.label(address(sellers[i]), string.concat("Seller#", vm.toString(i + 1)));
        }
        _;
    }

    /// @notice Helper to setup oracle task
    function setupOracleTask(SwanAgent agent, uint256 taskId) internal {
        // Move to withdraw phase
        increaseTime(
            agent.createdAt() + marketParameters.listingInterval + marketParameters.buyInterval,
            agent,
            SwanAgent.Phase.Withdraw,
            0
        );

        uint256 oracleFee = swan.getOracleFee();

        // Fund agent for oracle fee
        vm.startPrank(address(agent));
        deal(address(token), address(agent), oracleFee);
        token.approve(address(swan.coordinator()), oracleFee);
        vm.stopPrank();

        // Register generators first
        for (uint256 i = 0; i < generators.length; i++) {
            vm.startPrank(generators[i]);
            deal(address(token), generators[i], stakes.generatorStakeAmount);
            token.approve(address(oracleRegistry), stakes.generatorStakeAmount);
            oracleRegistry.register(LLMOracleKind.Generator);
            vm.stopPrank();
        }

        // Add validator to whitelist and register BEFORE any oracle interactions
        vm.startPrank(dria);
        address[] memory validatorArray = new address[](1);
        validatorArray[0] = validators[0];
        oracleRegistry.addToWhitelist(validatorArray);
        vm.stopPrank();

        vm.startPrank(validators[0]);
        deal(address(token), validators[0], stakes.validatorStakeAmount);
        token.approve(address(oracleRegistry), stakes.validatorStakeAmount);
        oracleRegistry.register(LLMOracleKind.Validator);
        vm.stopPrank();

        // Now make oracle request
        vm.prank(agentOwners[0]);
        agent.oracleStateRequest(input, models);

        // Process responses
        safeRespond(generators[0], TEST_OUTPUT, taskId);
        safeRespond(generators[1], TEST_OUTPUT, taskId);
        safeValidate(validators[0], taskId);

        // Verify task completed
        (
            address requester,
            bytes32 protocol,
            LLMOracleTaskParameters memory parameters,
            LLMOracleTask.TaskStatus status,
            uint256 generatorFee,
            uint256 validatorFee,
            uint256 platformFee,
            bytes memory taskInput,
            bytes memory taskModels
        ) = swan.coordinator().requests(taskId);

        assertEq(uint8(status), uint8(LLMOracleTask.TaskStatus.Completed));
    }

    /// @notice Owner can set authorization status
    function test_setAuthorization() external {
        address auth = makeAddr("authorized");

        // Non-owner cannot set authorization
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        lottery.setAuthorization(auth, true);

        vm.startPrank(lottery.owner());

        vm.recordLogs();
        lottery.setAuthorization(auth, true);
        assertTrue(lottery.authorized(auth));

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("AuthorizationUpdated(address,bool)"));

        lottery.setAuthorization(auth, false);
        assertFalse(lottery.authorized(auth));

        vm.stopPrank();
    }

    /// @notice Only owner can set claim window
    function test_setClaimWindow() external {
        uint256 newWindow = 5;

        // Non-owner cannot set window
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        lottery.setClaimWindow(newWindow);

        vm.startPrank(lottery.owner());

        // Cannot set zero window
        vm.expectRevert(SwanLottery.InvalidClaimWindow.selector);
        lottery.setClaimWindow(0);

        vm.recordLogs();
        lottery.setClaimWindow(newWindow);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("ClaimWindowUpdated(uint256,uint256)"));

        assertEq(lottery.claimWindow(), newWindow);
        vm.stopPrank();
    }

    /// @notice Full claim rewards flow test
    function test_claimRewards()
        external
        fund
        createAgents
        sellersApproveToSwan
        listArtifacts(sellers[0], 1, address(agents[0]))
        addValidatorsToWhitelist
        registerOracles
    {
        address artifact = swan.getListedArtifacts(address(agents[0]), currRound)[0];
        SwanAgent agent = agents[0];
        uint256 price = swan.getListingPrice(artifact);

        vm.startPrank(lottery.owner());
        lottery.setAuthorization(address(this), true);
        vm.stopPrank();

        // Purchase using the agent
        increaseTime(agent.createdAt() + marketParameters.listingInterval, agent, SwanAgent.Phase.Buy, 0);
        vm.startPrank(address(agent));
        deal(address(token), address(agent), price);
        swan.purchase(artifact);
        vm.stopPrank();

        // Setup oracle task
        setupOracleTask(agent, 1);

        // Approve tokens for lottery
        vm.startPrank(swan.owner());
        deal(address(token), swan.owner(), 100 ether);
        token.approve(address(lottery), type(uint256).max);
        vm.stopPrank();

        // Claim rewards
        vm.startPrank(address(this));
        vm.recordLogs();
        uint256 originalMultiplier = lottery.computeMultiplier(artifact);

        // If multiplier is 1x, test NoBonusAvailable revert
        if (originalMultiplier <= BASIS_POINTS) {
            vm.expectRevert(abi.encodeWithSelector(SwanLottery.NoBonusAvailable.selector, artifact, originalMultiplier));
            lottery.claimRewards(artifact);
        } else {
            // If multiplier > 1x, test successful claim
            lottery.claimRewards(artifact);
            assertTrue(lottery.rewardsClaimed(artifact));
            assertEq(lottery.artifactMultipliers(artifact), originalMultiplier);
        }
        vm.stopPrank();
    }

    /// @notice Verify multiplier probability distribution
    function test_probabilityDistribution() external view {
        uint256 samples = 10000;
        uint256[6] memory counts;

        for (uint256 i = 0; i < samples; i++) {
            bytes32 rand = keccak256(abi.encodePacked(i));
            uint256 multiplier = lottery.selectMultiplier(uint256(rand) % lottery.BASIS_POINTS());

            if (multiplier == lottery.BASIS_POINTS()) counts[0]++; // 1x

            else if (multiplier == 2 * lottery.BASIS_POINTS()) counts[1]++; // 2x

            else if (multiplier == 3 * lottery.BASIS_POINTS()) counts[2]++; // 3x

            else if (multiplier == 5 * lottery.BASIS_POINTS()) counts[3]++; // 5x

            else if (multiplier == 10 * lottery.BASIS_POINTS()) counts[4]++; // 10x

            else if (multiplier == 20 * lottery.BASIS_POINTS()) counts[5]++; // 20x
        }

        // 8% margin test
        assertApproxEqRel(counts[0], samples * 75 / 100, 0.08e18); // ~75%
        assertApproxEqRel(counts[1], samples * 15 / 100, 0.08e18); // ~15%
        assertApproxEqRel(counts[2], samples * 5 / 100, 0.08e18); // ~5%
        assertApproxEqRel(counts[3], samples * 3 / 100, 0.08e18); // ~3%
        assertApproxEqRel(counts[4], samples * 15 / 1000, 0.08e18); // ~1.5%
        assertApproxEqRel(counts[5], samples * 5 / 1000, 0.08e18); // ~0.5%
    }

    /// @notice Test claim rewards reverts
    function test_RevertWhen_InvalidClaimRewards()
        external
        fund
        createAgents
        sellersApproveToSwan
        listArtifacts(sellers[0], 1, address(agents[0]))
    {
        address artifact = swan.getListedArtifacts(address(agents[0]), currRound)[0];

        vm.startPrank(lottery.owner());
        lottery.setAuthorization(address(this), true);
        vm.stopPrank();

        // Test ArtifactNotSold error
        bytes memory expectedError = abi.encodeWithSignature("ArtifactNotSold(address)", artifact);
        vm.expectRevert(expectedError);
        lottery.claimRewards(artifact);
    }

    /// @notice Test reward calculations
    function test_getRewards()
        external
        fund
        createAgents
        sellersApproveToSwan
        listArtifacts(sellers[0], 1, address(agents[0]))
        addValidatorsToWhitelist
        registerOracles
    {
        address artifact = swan.getListedArtifacts(address(agents[0]), currRound)[0];

        // Rewards should be 0 until claimed since artifactMultipliers is empty
        assertEq(lottery.getRewards(artifact), 0);

        // Setup authorization
        vm.startPrank(lottery.owner());
        lottery.setAuthorization(address(this), true);
        vm.stopPrank();

        // Make sale
        SwanAgent agent = agents[0];
        increaseTime(agent.createdAt() + marketParameters.listingInterval, agent, SwanAgent.Phase.Buy, 0);
        vm.startPrank(address(agent));
        deal(address(token), address(agent), swan.getListingPrice(artifact));
        swan.purchase(artifact);
        vm.stopPrank();

        // Setup oracle task
        setupOracleTask(agent, 1);

        // Setup for claim
        vm.startPrank(swan.owner());
        deal(address(token), swan.owner(), 100 ether);
        token.approve(address(lottery), type(uint256).max);
        vm.stopPrank();

        // Check multiplier without rolling blocks
        uint256 multiplier = lottery.computeMultiplier(artifact);
        vm.startPrank(address(this));

        if (multiplier <= BASIS_POINTS) {
            // Test revert case for 1x multiplier
            vm.expectRevert(abi.encodeWithSelector(SwanLottery.NoBonusAvailable.selector, artifact, multiplier));
            lottery.claimRewards(artifact);
        } else {
            // Test success case for >1x multiplier
            lottery.claimRewards(artifact);
            assertEq(lottery.artifactMultipliers(artifact), multiplier);
            assertEq(lottery.getRewards(artifact), (agent.listingFee() * multiplier) / BASIS_POINTS);
        }
        vm.stopPrank();
    }

    /// @notice Test double claim prevention
    function test_RevertWhen_DoubleClaim()
        external
        fund
        createAgents
        sellersApproveToSwan
        listArtifacts(sellers[0], 1, address(agents[0]))
        addValidatorsToWhitelist
        registerOracles
    {
        address artifact = swan.getListedArtifacts(address(agents[0]), currRound)[0];
        SwanAgent agent = agents[0];

        vm.startPrank(lottery.owner());
        lottery.setAuthorization(address(this), true);
        vm.roll(block.number + 1);
        vm.stopPrank();

        // Sell artifact
        increaseTime(agent.createdAt() + marketParameters.listingInterval, agent, SwanAgent.Phase.Buy, 0);
        vm.startPrank(address(agent));
        deal(address(token), address(agent), swan.getListingPrice(artifact));
        swan.purchase(artifact);
        vm.stopPrank();

        // Setup oracle task
        setupOracleTask(agent, 1);

        // Setup for claim
        vm.startPrank(swan.owner());
        deal(address(token), swan.owner(), 100 ether);
        token.approve(address(lottery), type(uint256).max);
        vm.stopPrank();

        // First claim
        vm.startPrank(address(this));
        lottery.claimRewards(artifact);

        // Try to claim again
        vm.expectRevert(abi.encodeWithSelector(SwanLottery.RewardAlreadyClaimed.selector, artifact));
        lottery.claimRewards(artifact);
        vm.stopPrank();
    }

    /// @notice Test invalid artifact cases
    function test_RevertWhen_InvalidArtifact() external {
        address invalidArtifact = makeAddr("invalid");

        vm.startPrank(lottery.owner());
        lottery.setAuthorization(address(this), true);

        bytes memory expectedError = abi.encodeWithSignature("InvalidArtifact(address)", invalidArtifact);
        vm.expectRevert(expectedError);
        lottery.claimRewards(invalidArtifact);
        vm.stopPrank();
    }
}
