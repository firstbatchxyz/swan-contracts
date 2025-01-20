// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Swan} from "./Swan.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract SwanLottery is Ownable {
    // Base const
    uint256 public constant BASIS_POINTS = 10000;

    struct MultiplierConfig {
        uint256 multiplier;
        uint256 probability;
    }

    Swan public immutable swan;
    ERC20 public immutable token;

    // Storage for multipliers and claims
    mapping(address => mapping(uint256 => uint256)) public artifactMultipliers; // artifact => round => multiplier
    mapping(address => mapping(uint256 => bool)) public rewardsClaimed; // artifact => round => claimed
    mapping(address => bool) public isAuthorized;

    modifier onlyAuthorized() {
        require(isAuthorized[msg.sender], "Not authorized");
        _;
    }

    event MultiplierAssigned(address indexed artifact, uint256 indexed round, uint256 multiplier);
    event RewardClaimed(address indexed seller, address indexed artifact, uint256 indexed round, uint256 reward);
    event AuthorizationUpdated(address indexed authorizer, bool status);

    constructor(address _swan, address initialOwner) Ownable(initialOwner) {
        swan = Swan(_swan);
        token = swan.token();
    }

    function assignMultiplier(address artifact, uint256 round) external onlyAuthorized {
        Swan.ArtifactListing memory listing = swan.getListing(artifact);
        require(listing.seller != address(0), "Invalid artifact");
        require(listing.round == round, "Wrong round");
        require(artifactMultipliers[artifact][round] == 0, "Already assigned");

        uint256 multiplier = _computeMultiplier(artifact, round);
        artifactMultipliers[artifact][round] = multiplier;
        emit MultiplierAssigned(artifact, round, multiplier);
    }

    function _computeMultiplier(address artifact, uint256 round) internal view returns (uint256) {
        // Utilize previous round's data
        bytes32 randomness = blockhash(block.number - 1);
        uint256 rand = uint256(
            keccak256(
                abi.encodePacked(
                    randomness, artifact, round, swan.getListing(artifact).seller, swan.getListing(artifact).agent
                )
            )
        ) % BASIS_POINTS;

        // example
        if (rand < 7500) return 1 * BASIS_POINTS; // 75% chance of 1x
        if (rand < 9000) return 2 * BASIS_POINTS; // 15% chance of 2x
        if (rand < 9500) return 3 * BASIS_POINTS; // 5% chance of 3x
        if (rand < 9800) return 5 * BASIS_POINTS; // 3% chance of 5x
        if (rand < 9950) return 10 * BASIS_POINTS; // 1.5% chance of 10x
        return 20 * BASIS_POINTS; // 0.5% chance of 20x
    }

    function claimRewards(address artifactAddress, uint256 round) public onlyAuthorized {
        require(!rewardsClaimed[artifactAddress][round], "Already claimed");

        // Get listing and compute randomness/multiplier
        Swan.ArtifactListing memory listing = swan.getListing(artifactAddress);
        require(listing.status == Swan.ArtifactStatus.Sold, "Not sold");
        require(listing.round == round, "Wrong round");

        uint256 reward = getRewards(artifactAddress, round);
        if (reward > 0) {
            rewardsClaimed[artifactAddress][round] = true;
            // Transfer reward from platform fees to seller
            token.transferFrom(swan.owner(), listing.seller, reward);
            emit RewardClaimed(listing.seller, artifactAddress, round, reward);
        }
    }

    // Check potential reward
    function getRewards(address artifact, uint256 round) public view returns (uint256) {
        Swan.ArtifactListing memory listing = swan.getListing(artifact);
        uint256 multiplier = artifactMultipliers[artifact][round];

        return (listing.listingFee * multiplier) / BASIS_POINTS;
    }

    function setAuthorization(address addr, bool status) external onlyOwner {
        isAuthorized[addr] = status;
        emit AuthorizationUpdated(addr, status);
    }
}
