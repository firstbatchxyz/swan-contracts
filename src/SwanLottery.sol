// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Swan} from "./Swan.sol";
import {SwanAgent} from "./SwanAgent.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract SwanLottery is Ownable {
    // CONSTANTS
    uint256 public constant BASIS_POINTS = 10000;

    // STORAGE
    Swan public immutable swan;
    ERC20 public immutable token;

    // number of rounds after listing that rewards can be claimed
    uint256 public claimWindow;

    // lottery data
    mapping(address artifact => mapping(uint256 round => uint256 multiplier)) public artifactMultipliers;
    mapping(address artifact => mapping(uint256 round => bool claimed)) public rewardsClaimed;
    mapping(address addr => bool isAllowed) public authorized;

    // EVENTS
    event AuthorizationUpdated(address indexed addr, bool status);
    event MultiplierAssigned(address indexed artifact, uint256 indexed round, uint256 multiplier);
    event RewardClaimed(address indexed seller, address indexed artifact, uint256 indexed round, uint256 reward);
    event ClaimWindowUpdated(uint256 oldWindow, uint256 newWindow);

    // ERRORS
    error Unauthorized(address caller);
    error InvalidClaimWindow();
    error MultiplierAlreadyAssigned(address artifact, uint256 round);
    error InvalidRound(uint256 current, uint256 required);
    error RewardAlreadyClaimed(address artifact, uint256 round);
    error ClaimWindowExpired(uint256 currentRound, uint256 listingRound, uint256 window);

    // MODIFIERS
    modifier onlyAuthorized() {
        if (!authorized[msg.sender]) revert Unauthorized(msg.sender);
        _;
    }

    /// @notice Constructor sets initial configuration
    /// @dev Sets Swan contract, token, and initial claim window
    constructor(address _swan, uint256 _claimWindow) Ownable(msg.sender) {
        swan = Swan(_swan);
        token = swan.token();
        authorized[msg.sender] = true;
        claimWindow = _claimWindow;
    }

    /// @notice Assigns multiplier to a newly listed artifact
    function assignMultiplier(address artifact, uint256 round) external onlyAuthorized {
        // verify listing exists
        Swan.ArtifactListing memory listing = swan.getListing(artifact);
        if (listing.seller == address(0)) revert("Invalid artifact");
        if (listing.round != round) revert InvalidRound(listing.round, round);

        // check multiplier not already assigned
        if (artifactMultipliers[artifact][round] != 0) {
            revert MultiplierAlreadyAssigned(artifact, round);
        }

        // compute and store multiplier
        uint256 randomness = _computeRandomness(artifact, round);
        uint256 multiplier = _selectMultiplier(randomness);

        artifactMultipliers[artifact][round] = multiplier;
        emit MultiplierAssigned(artifact, round, multiplier);
    }

    /// @notice Public view of multiplier computation
    function computeMultiplier(address artifact, uint256 round) public view returns (uint256) {
        return _selectMultiplier(_computeRandomness(artifact, round));
    }

    /// @notice Compute randomness for multiplier
    function _computeRandomness(address artifact, uint256 round) internal view returns (uint256) {
        bytes32 randomness = blockhash(block.number - 1);
        return uint256(
            keccak256(
                abi.encodePacked(
                    randomness, artifact, round, swan.getListing(artifact).seller, swan.getListing(artifact).agent
                )
            )
        ) % BASIS_POINTS;
    }

    /// @notice Select multiplier based on random value
    function _selectMultiplier(uint256 rand) public pure returns (uint256) {
        // 75% chance of 1x
        if (rand < 7500) return BASIS_POINTS;
        // 15% chance of 2x
        if (rand < 9000) return 2 * BASIS_POINTS;
        // 5% chance of 3x
        if (rand < 9500) return 3 * BASIS_POINTS;
        // 3% chance of 5x
        if (rand < 9800) return 5 * BASIS_POINTS;
        // 1.5% chance of 10x
        if (rand < 9950) return 10 * BASIS_POINTS;
        // 0.5% chance of 20x
        return 20 * BASIS_POINTS;
    }

    /// @notice Claims rewards for sold artifacts within claim window
    function claimRewards(address artifact, uint256 round) public onlyAuthorized {
        // Check not already claimed
        if (rewardsClaimed[artifact][round]) revert RewardAlreadyClaimed(artifact, round);

        // Get listing and validate
        Swan.ArtifactListing memory listing = swan.getListing(artifact);
        if (listing.status != Swan.ArtifactStatus.Sold) revert("Not sold");
        if (listing.round != round) revert InvalidRound(listing.round, round);

        // Check claim window using agent's round
        (uint256 currentRound,,) = SwanAgent(listing.agent).getRoundPhase();
        if (currentRound > listing.round + claimWindow) {
            revert ClaimWindowExpired(currentRound, listing.round, claimWindow);
        }

        // Check multiplier and compute reward
        uint256 multiplier = artifactMultipliers[artifact][round];
        if (multiplier <= BASIS_POINTS) revert("No bonus available");

        uint256 reward = getRewards(artifact, round);
        if (reward > 0) {
            rewardsClaimed[artifact][round] = true;
            token.transferFrom(swan.owner(), listing.seller, reward);
            emit RewardClaimed(listing.seller, artifact, round, reward);
        }
    }

    /// @notice Calculate potential reward
    function getRewards(address artifact, uint256 round) public view returns (uint256) {
        Swan.ArtifactListing memory listing = swan.getListing(artifact);
        uint256 multiplier = artifactMultipliers[artifact][round];
        return (listing.listingFee * multiplier) / BASIS_POINTS;
    }

    /// @notice Update authorization status
    function setAuthorization(address addr, bool status) external onlyOwner {
        authorized[addr] = status;
        emit AuthorizationUpdated(addr, status);
    }

    /// @notice Update claim window
    /// @dev Only owner can call
    function setClaimWindow(uint256 newWindow) external onlyOwner {
        if (newWindow == 0) revert InvalidClaimWindow();
        uint256 oldWindow = claimWindow;
        claimWindow = newWindow;
        emit ClaimWindowUpdated(oldWindow, newWindow);
    }
}
