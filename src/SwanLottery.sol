// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Swan} from "./Swan.sol";
import {SwanAgent} from "./SwanAgent.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title Swan Lottery Contract
contract SwanLottery is Ownable {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Used to calculate rewards and multipliers with proper decimal precision.
    uint256 public constant BASIS_POINTS = 10000;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Main Swan contract instance.
    Swan public immutable swan;
    /// @notice Token used for rewards and payments.
    ERC20 public immutable token;

    /// @notice Number of rounds after listing that rewards can be claimed.
    uint256 public claimWindow;

    /// @notice Maps artifact and round to its assigned multiplier.
    mapping(address artifact => mapping(uint256 round => uint256 multiplier)) public artifactMultipliers;
    /// @notice Tracks whether rewards have been claimed for an artifact in a specific round.
    mapping(address artifact => mapping(uint256 round => bool claimed)) public rewardsClaimed;
    /// @notice Maps addresses to their authorization status for lottery operations.
    mapping(address addr => bool isAllowed) public authorized;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an address's authorization status is updated.
    /// @param addr The address whose authorization was updated.
    /// @param status The new authorization status.
    event AuthorizationUpdated(address indexed addr, bool status);

    /// @notice Emitted when a multiplier is assigned to an artifact.
    /// @param artifact The address of the artifact.
    /// @param round The round number. TODO: can be removed
    /// @param multiplier The assigned multiplier value.
    event MultiplierAssigned(address indexed artifact, uint256 indexed round, uint256 multiplier);

    /// @notice Emitted when a reward is claimed for an artifact.
    /// @param seller The address of the artifact seller.
    /// @param artifact The address of the artifact.
    /// @param round The round number. TODO: can be removed
    /// @param reward The amount of reward claimed.
    event RewardClaimed(address indexed seller, address indexed artifact, uint256 indexed round, uint256 reward);

    /// @notice Emitted when the claim window duration is updated.
    /// @param oldWindow Previous claim window value.
    /// @param newWindow New claim window value.
    event ClaimWindowUpdated(uint256 oldWindow, uint256 newWindow);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Caller is not authorized for the operation.
    error Unauthorized(address caller);
    /// @notice Invalid claim window value provided.
    error InvalidClaimWindow();
    /// @notice Multiplier has already been assigned for this artifact and round.
    error MultiplierAlreadyAssigned(address artifact, uint256 round);
    /// @notice Round number mismatch between current and required.
    error InvalidRound(uint256 current, uint256 required);
    /// @notice Reward has already been claimed for this artifact and round.
    error RewardAlreadyClaimed(address artifact, uint256 round);
    /// @notice Claim window has expired for the artifact.
    error ClaimWindowExpired(uint256 currentRound, uint256 listingRound, uint256 window);
    /// @notice Invalid artifact address provided.
    error InvalidArtifact(address artifact);
    /// @notice Artifact is not in sold status.
    error ArtifactNotSold(address artifact);
    /// @notice No bonus available for the artifact with given multiplier.
    error NoBonusAvailable(address artifact, uint256 multiplier);
    /// @notice No reward available for the artifact in the given round.
    error NoRewardAvailable(address artifact, uint256 round);

    /*//////////////////////////////////////////////////////////////
                                 MODIFIERS
    //////////////////////////////////////////////////////////////*/

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
    /// TODO: remove round number
    function assignMultiplier(address artifact, uint256 round) external onlyAuthorized {
        // verify listing exists
        Swan.ArtifactListing memory listing = swan.getListing(artifact);
        if (listing.seller == address(0)) revert InvalidArtifact(artifact);
        if (listing.round != round) revert InvalidRound(listing.round, round);

        // check multiplier not already assigned
        if (artifactMultipliers[artifact][round] != 0) {
            revert MultiplierAlreadyAssigned(artifact, round);
        }

        // compute and store multiplier
        uint256 randomness = _computeRandomness(artifact, round);
        uint256 multiplier = selectMultiplier(randomness);

        artifactMultipliers[artifact][round] = multiplier;
        emit MultiplierAssigned(artifact, round, multiplier);
    }

    /// @notice Public view of multiplier computation
    function computeMultiplier(address artifact, uint256 round) external view returns (uint256) {
        return selectMultiplier(_computeRandomness(artifact, round));
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
    function selectMultiplier(uint256 rand) public pure returns (uint256) {
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
    function claimRewards(address artifact, uint256 round) external onlyAuthorized {
        // check not already claimed
        if (rewardsClaimed[artifact][round]) revert RewardAlreadyClaimed(artifact, round);

        // get listing and validate
        Swan.ArtifactListing memory listing = swan.getListing(artifact);
        if (listing.status != Swan.ArtifactStatus.Sold) revert ArtifactNotSold(artifact);
        if (listing.round != round) revert InvalidRound(listing.round, round);

        // check claim window using agent's round
        (uint256 currentRound,,) = SwanAgent(listing.agent).getRoundPhase();
        if (currentRound > listing.round + claimWindow) {
            revert ClaimWindowExpired(currentRound, listing.round, claimWindow);
        }

        // check multiplier and compute reward
        uint256 multiplier = artifactMultipliers[artifact][round];
        if (multiplier <= BASIS_POINTS) revert NoBonusAvailable(artifact, multiplier);

        uint256 reward = getRewards(artifact, round);
        if (reward == 0) revert NoRewardAvailable(artifact, round);

        rewardsClaimed[artifact][round] = true;
        token.transferFrom(swan.owner(), listing.seller, reward);
        emit RewardClaimed(listing.seller, artifact, round, reward);
    }

    /// @notice Calculate potential reward for an artifact.
    /// @param artifact The address of the artifact.
    /// @param round The round number.
    function getRewards(address artifact, uint256 round) public view returns (uint256) {
        Swan.ArtifactListing memory listing = swan.getListing(artifact);
        uint256 multiplier = artifactMultipliers[artifact][round];
        return (listing.listingFee * multiplier) / BASIS_POINTS;
    }

    /// @notice Update authorization status.
    /// @dev Only owner can call.
    /// @param addr The address to update authorization status for.
    /// @param status The new authorization status.
    function setAuthorization(address addr, bool status) external onlyOwner {
        authorized[addr] = status;
        emit AuthorizationUpdated(addr, status);
    }

    /// @notice Update claim window.
    /// @dev Only owner can call.
    /// @param newWindow The new claim window duration.
    function setClaimWindow(uint256 newWindow) external onlyOwner {
        if (newWindow == 0) revert InvalidClaimWindow();
        emit ClaimWindowUpdated(claimWindow, newWindow);
        claimWindow = newWindow;
    }
}
