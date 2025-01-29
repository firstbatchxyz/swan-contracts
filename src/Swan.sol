// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {
    LLMOracleCoordinator, LLMOracleTaskParameters
} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";
import {SwanAgentFactory, SwanAgent} from "./SwanAgent.sol";
import {SwanArtifactFactory, SwanArtifact} from "./SwanArtifact.sol";
import {SwanManager, SwanMarketParameters} from "./SwanManager.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @dev Protocol string for Swan Purchase CRONs, checked in the Oracle.
bytes32 constant SwanAgentPurchaseOracleProtocol = "swan-agent-purchase/0.1.0";
/// @dev Protocol string for Swan State CRONs, checked in the Oracle.
bytes32 constant SwanAgentStateOracleProtocol = "swan-agent-state/0.1.0";

/// @dev Used to calculate the fee for the agent to be able to compute correct amount.
uint256 constant BASIS_POINTS = 10_000;

contract Swan is SwanManager, UUPSUpgradeable {
    using Math for uint256;
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Invalid artifact status.
    error InvalidStatus(ArtifactStatus have, ArtifactStatus want);

    /// @notice Caller is not authorized for the operation, e.g. not a contract owner or listing owner.
    error Unauthorized(address caller);

    /// @notice The given artifact is still in the given round.
    /// @dev Most likely coming from `relist` function, where the artifact cant be
    /// relisted in the same round that it was listed in.
    error RoundNotFinished(address artifact, uint256 round);

    /// @notice Artifact count limit exceeded for this round
    error ArtifactLimitExceeded(uint256 limit);

    /// @notice Invalid price for the artifact.
    error InvalidPrice(uint256 price);
    error InsufficientBudget(uint256 required, uint256 available);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Artifact is created & listed for sale.
    event ArtifactListed(address indexed owner, address indexed artifact, uint256 price);

    /// @notice Artifact relisted by it's `owner`.
    /// @dev This may happen if a listed artifact is not sold in the current round, and is relisted in a new round.
    event ArtifactRelisted(address indexed owner, address indexed agent, address indexed artifact, uint256 price);

    /// @notice An `agent` purchased an artifact.
    event ArtifactSold(address indexed owner, address indexed agent, address indexed artifact, uint256 price);

    /// @notice A new agent is created.
    /// @dev `owner` is the owner of the agent.
    /// @dev `agent` is the address of the agent.
    event AgentCreated(address indexed owner, address indexed agent);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Status of an artifact. All artifacts are listed as soon as they are listed.
    /// @dev Unlisted: Cannot be purchased in the current round.
    /// @dev Listed: Can be purchase in the current round.
    /// @dev Sold: Artifact is sold.
    /// @dev It is important that `Unlisted` is only the default and is not set explicitly.
    /// This allows to understand that if an artifact is `Listed` but the round has past, it was not sold.
    /// The said fact is used within the `relist` logic.
    enum ArtifactStatus {
        Unlisted,
        Listed,
        Sold
    }

    /// @notice Holds the listing information.
    /// @dev `createdAt` is the timestamp of the artifact creation.
    /// @dev `listingFee` is the listing fee of the agent.
    /// @dev `price` is the price of the artifact.
    /// @dev `seller` is the address of the creator of the artifact.
    /// @dev `agent` is the address of the agent.
    /// @dev `round` is the round in which the artifact is created.
    /// @dev `status` is the status of the artifact.
    struct ArtifactListing {
        uint256 createdAt;
        uint96 listingFee;
        uint256 price;
        address seller; // TODO: we can use artifact.owner() instead of seller
        address agent;
        uint256 round;
        ArtifactStatus status;
    }

    /// @notice Factory contract to deploy Agents.
    SwanAgentFactory public agentFactory;
    /// @notice Factory contract to deploy Artifact tokens.
    SwanArtifactFactory public artifactFactory;

    /// @notice To keep track of the artifacts for purchase.
    mapping(address artifact => ArtifactListing) public listings;
    /// @notice Keeps track of artifacts per agent & round.
    mapping(address agent => mapping(uint256 round => address[])) public artifactsPerAgentRound;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Locks the contract, preventing any future re-initialization.
    /// @dev [See more](https://docs.openzeppelin.com/contracts/5.x/api/proxy#Initializable-_disableInitializers--).
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                                UPGRADABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Upgrades to contract with a new implementation.
    /// @dev Only callable by the owner.
    /// @param newImplementation address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        // `onlyOwner` modifier does the auth here
    }

    /// @notice Initialize the contract.
    function initialize(
        SwanMarketParameters calldata _marketParameters,
        LLMOracleTaskParameters calldata _oracleParameters,
        // contracts
        address _coordinator,
        address _token,
        address _agentFactory,
        address _artifactFactory
    ) public initializer {
        __Ownable_init(msg.sender);

        require(_marketParameters.platformFee <= 100, "Platform fee cannot exceed 100%");

        // market & oracle parameters
        marketParameters.push(_marketParameters);
        oracleParameters = _oracleParameters;

        // contracts
        coordinator = LLMOracleCoordinator(_coordinator);
        token = ERC20(_token);
        agentFactory = SwanAgentFactory(_agentFactory);
        artifactFactory = SwanArtifactFactory(_artifactFactory);

        // swan is an operator
        isOperator[address(this)] = true;
        // owner is an operator
        isOperator[msg.sender] = true;
    }

    /// @notice Transfer ownership of the contract.
    /// @dev Overrides the default `transferOwnership` function to make the new owner an operator.
    /// @param newOwner address of the new owner.
    function transferOwnership(address newOwner) public override onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        // remove the old owner from the operator list
        isOperator[msg.sender] = false;

        // transfer ownership
        _transferOwnership(newOwner);

        // make new owner an operator
        isOperator[newOwner] = true;
    }

    /*//////////////////////////////////////////////////////////////
                                  LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new agent.
    /// @dev Emits a `AgentCreated` event.
    /// @return address of the new agent.
    function createAgent(
        string calldata _name,
        string calldata _description,
        uint96 _listingFee,
        uint256 _amountPerRound
    ) external returns (SwanAgent) {
        SwanAgent agent = agentFactory.deploy(_name, _description, _listingFee, _amountPerRound, msg.sender);
        emit AgentCreated(msg.sender, address(agent));

        return agent;
    }

    /// @notice Creates a new artifact.
    /// @param _name name of the token.
    /// @param _symbol symbol of the token.
    /// @param _desc description of the token.
    /// @param _price price of the token.
    /// @param _agent address of the agent.
    function list(string calldata _name, string calldata _symbol, bytes calldata _desc, uint256 _price, address _agent)
        external
    {
        SwanAgent agent = SwanAgent(_agent);
        (uint256 round, SwanAgent.Phase phase,) = agent.getRoundPhase();

        // agent must be in the listing phase
        if (phase != SwanAgent.Phase.Listing) {
            revert SwanAgent.InvalidPhase(phase, SwanAgent.Phase.Listing);
        }
        // artifact count must not exceed `maxArtifactCount`
        if (getCurrentMarketParameters().maxArtifactCount == artifactsPerAgentRound[_agent][round].length) {
            revert ArtifactLimitExceeded(getCurrentMarketParameters().maxArtifactCount);
        }
        // check the artifact price is within the acceptable range
        if (_price < getCurrentMarketParameters().minArtifactPrice || _price >= agent.amountPerRound()) {
            revert InvalidPrice(_price);
        }

        // all is well, create the artifact & its listing
        address artifact = address(artifactFactory.deploy(_name, _symbol, _desc, msg.sender));
        listings[artifact] = ArtifactListing({
            createdAt: block.timestamp,
            listingFee: agent.listingFee(),
            price: _price,
            seller: msg.sender,
            status: ArtifactStatus.Listed,
            agent: _agent,
            round: round
        });

        // add this to list of listings for the agent for this round
        artifactsPerAgentRound[_agent][round].push(artifact);

        // transfer royalties
        transferListingFees(listings[artifact]);

        emit ArtifactListed(msg.sender, artifact, _price);
    }

    /// @notice Relist the artifact for another round and/or another agent and/or another price.
    /// @param  _artifact address of the artifact.
    /// @param  _agent new agent for the artifact.
    /// @param  _price new price of the token.
    function relist(address _artifact, address _agent, uint256 _price) external {
        ArtifactListing storage artifact = listings[_artifact];

        // only the seller can relist the artifact
        if (artifact.seller != msg.sender) {
            revert Unauthorized(msg.sender);
        }

        // artifact must be listed
        if (artifact.status != ArtifactStatus.Listed) {
            revert InvalidStatus(artifact.status, ArtifactStatus.Listed);
        }

        // relist can only happen after the round of its listing has ended
        // we check this via the old agent, that is the existing artifact.agent
        //
        // note that artifact is unlisted here, but is not bought at all
        //
        // perhaps it suffices to check `==` here, since agent round
        // is changed incrementially
        (uint256 oldRound,,) = SwanAgent(artifact.agent).getRoundPhase();
        if (oldRound <= artifact.round) {
            revert RoundNotFinished(_artifact, artifact.round);
        }

        // check the artifact price is within the acceptable range
        if (_price < getCurrentMarketParameters().minArtifactPrice || _price >= SwanAgent(_agent).amountPerRound()) {
            revert InvalidPrice(_price);
        }

        // now we move on to the new agent
        SwanAgent agent = SwanAgent(_agent);
        (uint256 round, SwanAgent.Phase phase,) = agent.getRoundPhase();

        // agent must be in listing phase
        if (phase != SwanAgent.Phase.Listing) {
            revert SwanAgent.InvalidPhase(phase, SwanAgent.Phase.Listing);
        }

        // agent must not have more than `maxArtifactCount` many artifacts
        uint256 count = artifactsPerAgentRound[_agent][round].length;
        if (count >= getCurrentMarketParameters().maxArtifactCount) {
            revert ArtifactLimitExceeded(count);
        }

        // create listing
        listings[_artifact] = ArtifactListing({
            createdAt: block.timestamp,
            listingFee: agent.listingFee(),
            price: _price,
            seller: msg.sender,
            status: ArtifactStatus.Listed,
            agent: _agent,
            round: round
        });

        // add this to list of listings for the agent for this round
        artifactsPerAgentRound[_agent][round].push(_artifact);

        // transfer royalties
        transferListingFees(listings[_artifact]);

        emit ArtifactRelisted(msg.sender, _agent, _artifact, _price);
    }

    /// @notice Function to transfer the fees to the seller & Dria.
    function transferListingFees(ArtifactListing storage _artifact) internal {
        // calculate fees
        uint256 totalFee = Math.mulDiv(_artifact.price, (_artifact.listingFee * 100), BASIS_POINTS);
        uint256 driaFee = Math.mulDiv(totalFee, (getCurrentMarketParameters().platformFee * 100), BASIS_POINTS);
        uint256 agentFee = totalFee - driaFee;

        // first, Swan receives the entire fee from seller
        // this allows only one approval from the seller's side
        token.transferFrom(_artifact.seller, address(this), totalFee);

        // send the agent's portion to them
        token.transfer(_artifact.agent, agentFee);

        // then it sends the remaining to Swan owner
        token.transfer(owner(), driaFee);
    }

    /// @notice Executes the purchase of a listing for a agent for the given artifact.
    /// @dev Must be called by the agent of the given artifact.
    function purchase(address _artifact) external {
        ArtifactListing storage listing = listings[_artifact];

        // artifact must be listed to be purchased
        if (listing.status != ArtifactStatus.Listed) {
            revert InvalidStatus(listing.status, ArtifactStatus.Listed);
        }

        // can only the agent can purchase the artifact
        if (listing.agent != msg.sender) {
            revert Unauthorized(msg.sender);
        }

        // check budget before proceeding
        uint256 agentBalance = token.balanceOf(msg.sender);
        if (agentBalance < listing.price) {
            revert InsufficientBudget(listing.price, agentBalance);
        }

        // update artifact status to be sold
        listing.status = ArtifactStatus.Sold;

        // transfer artifact from seller to Swan, and then from Swan to agent
        // this ensure that only approval to Swan is enough for the sellers
        SwanArtifact(_artifact).transferFrom(listing.seller, address(this), 1);
        SwanArtifact(_artifact).transferFrom(address(this), listing.agent, 1);

        // transfer money
        token.transferFrom(listing.agent, address(this), listing.price);
        token.transfer(listing.seller, listing.price);

        emit ArtifactSold(listing.seller, msg.sender, _artifact, listing.price);
    }

    /// @notice Set the factories for Agents and Artifacts.
    /// @dev Only callable by owner.
    /// @param _agentFactory new SwanAgentFactory address
    /// @param _artifactFactory new SwanArtifactFactory address
    function setFactories(address _agentFactory, address _artifactFactory) external onlyOwner {
        agentFactory = SwanAgentFactory(_agentFactory);
        artifactFactory = SwanArtifactFactory(_artifactFactory);
    }

    /// @notice Returns the artifact price with the given artifact address.
    function getListingPrice(address _artifact) external view returns (uint256) {
        return listings[_artifact].price;
    }

    /// @notice Returns the number of artifacts with the given agent and round.
    function getListedArtifacts(address _agent, uint256 _round) external view returns (address[] memory) {
        return artifactsPerAgentRound[_agent][_round];
    }

    /// @notice Returns the artifact listing with the given artifact address.
    function getListing(address _artifact) external view returns (ArtifactListing memory) {
        return listings[_artifact];
    }
}
