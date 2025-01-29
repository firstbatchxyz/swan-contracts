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

contract SwanLotteryTest is Helper {
    uint256 public constant BASIS_POINTS = 10000;

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

    /// @notice Authorized users can assign multiplier
    function test_assignMultiplier()
        external
        fund
        createAgents
        sellersApproveToSwan
        listArtifacts(sellers[0], 1, address(agents[0]))
    {
        address artifact = swan.getListedArtifacts(address(agents[0]), currRound)[0];

        // Unauthorized cannot assign
        vm.expectRevert(abi.encodeWithSelector(SwanLottery.Unauthorized.selector, address(this)));
        lottery.assignMultiplier(artifact, currRound);

        vm.startPrank(lottery.owner());
        lottery.setAuthorization(address(this), true);

        vm.recordLogs();
        lottery.assignMultiplier(artifact, currRound);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("MultiplierAssigned(address,uint256,uint256)"));

        uint256 multiplier = lottery.artifactMultipliers(artifact, currRound);
        assertTrue(multiplier > 0);
        assertTrue(multiplier <= 20 * lottery.BASIS_POINTS());

        vm.stopPrank();
    }

    /// @notice Cannot assign multiplier twice or with invalid params
    function test_RevertWhen_InvalidAssignMultiplier()
        external
        fund
        createAgents
        sellersApproveToSwan
        listArtifacts(sellers[0], 1, address(agents[0]))
    {
        address artifact = swan.getListedArtifacts(address(agents[0]), currRound)[0];

        vm.startPrank(lottery.owner());
        lottery.setAuthorization(address(this), true);

        // Wrong round
        vm.expectRevert(abi.encodeWithSelector(SwanLottery.InvalidRound.selector, currRound, currRound + 1));
        lottery.assignMultiplier(artifact, currRound + 1);

        lottery.assignMultiplier(artifact, currRound);

        // Cannot assign twice
        vm.expectRevert(abi.encodeWithSelector(SwanLottery.MultiplierAlreadyAssigned.selector, artifact, currRound));
        lottery.assignMultiplier(artifact, currRound);

        vm.stopPrank();
    }

    /// @notice Full claim rewards flow test
    function test_claimRewards()
        external
        fund
        createAgents
        sellersApproveToSwan
        listArtifacts(sellers[0], 1, address(agents[0]))
    {
        address artifact = swan.getListedArtifacts(address(agents[0]), currRound)[0];
        SwanAgent agent = agents[0];
        uint256 price = swan.getListingPrice(artifact);

        // Force a multiplier greater than 1x (10000)
        vm.startPrank(lottery.owner());
        lottery.setAuthorization(address(this), true);

        // Mock the randomness to ensure higher multiplier
        vm.roll(block.number + 1); // New block for randomness
        lottery.assignMultiplier(artifact, currRound);
        vm.stopPrank();

        // Verify multiplier
        uint256 multiplier = lottery.artifactMultipliers(artifact, currRound);
        require(multiplier > BASIS_POINTS, "Multiplier must be > 1x");

        increaseTime(agent.createdAt() + marketParameters.listingInterval, agent, SwanAgent.Phase.Buy, 0);

        // Purchase using the agent
        vm.startPrank(address(agent));
        deal(address(token), address(agent), price);
        swan.purchase(artifact);
        vm.stopPrank();

        // Approve tokens for lottery
        vm.startPrank(swan.owner());
        deal(address(token), swan.owner(), 100 ether);
        token.approve(address(lottery), type(uint256).max);
        vm.stopPrank();

        // Claim rewards
        vm.startPrank(address(this));
        lottery.claimRewards(artifact, currRound);
        assertTrue(lottery.rewardsClaimed(artifact, currRound));
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
        lottery.claimRewards(artifact, currRound);
    }

    /// @notice Test reward calculations
    function test_getRewards()
        external
        fund
        createAgents
        sellersApproveToSwan
        listArtifacts(sellers[0], 1, address(agents[0]))
    {
        address artifact = swan.getListedArtifacts(address(agents[0]), currRound)[0];
        uint96 listingFee = agents[0].listingFee();

        vm.startPrank(lottery.owner());
        lottery.setAuthorization(address(this), true);
        lottery.assignMultiplier(artifact, currRound);
        vm.stopPrank();

        uint256 multiplier = lottery.artifactMultipliers(artifact, currRound);
        uint256 expectedReward = (listingFee * multiplier) / BASIS_POINTS;

        assertEq(lottery.getRewards(artifact, currRound), expectedReward);
    }

    /// @notice Test double claim prevention
    function test_RevertWhen_DoubleClaim()
        external
        fund
        createAgents
        sellersApproveToSwan
        listArtifacts(sellers[0], 1, address(agents[0]))
    {
        address artifact = swan.getListedArtifacts(address(agents[0]), currRound)[0];
        SwanAgent agent = agents[0];

        vm.startPrank(lottery.owner());
        lottery.setAuthorization(address(this), true);
        vm.roll(block.number + 1);
        lottery.assignMultiplier(artifact, currRound);
        assertGt(lottery.artifactMultipliers(artifact, currRound), BASIS_POINTS);
        vm.stopPrank();

        // Sell artifact
        increaseTime(agent.createdAt() + marketParameters.listingInterval, agent, SwanAgent.Phase.Buy, 0);
        vm.startPrank(address(agent));
        deal(address(token), address(agent), swan.getListingPrice(artifact));
        swan.purchase(artifact);
        vm.stopPrank();

        // Setup for claim
        vm.startPrank(swan.owner());
        deal(address(token), swan.owner(), 100 ether);
        token.approve(address(lottery), type(uint256).max);
        vm.stopPrank();

        // First claim
        vm.startPrank(address(this));
        lottery.claimRewards(artifact, currRound);

        // Try to claim again
        vm.expectRevert(abi.encodeWithSelector(SwanLottery.RewardAlreadyClaimed.selector, artifact, currRound));
        lottery.claimRewards(artifact, currRound);
        vm.stopPrank();
    }

    /// @notice Test invalid artifact cases
    function test_RevertWhen_InvalidArtifact() external {
        address invalidArtifact = makeAddr("invalid");

        vm.startPrank(lottery.owner());
        lottery.setAuthorization(address(this), true);

        bytes memory expectedError = abi.encodeWithSignature("InvalidArtifact(address)", invalidArtifact);
        vm.expectRevert(expectedError);
        lottery.assignMultiplier(invalidArtifact, 0);
        vm.stopPrank();
    }
}
