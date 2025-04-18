// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    LLMOracleTask,
    LLMOracleTaskParameters,
    LLMOracleCoordinator
} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";

/// @notice Collection of market-related parameters.
/// @dev Prevents stack-too-deep.
struct SwanMarketParameters {
    /// @notice The interval at which the agent can withdraw the funds.
    uint256 withdrawInterval;
    /// @notice The interval at which the creators can mint artifacts.
    uint256 listingInterval;
    /// @notice The interval at which the agent can buy the artifacts.
    uint256 buyInterval;
    /// @notice A fee percentage taken from each listing's agent fee.
    uint256 platformFee;
    /// @notice The maximum number of artifacts that can be listed per round.
    uint256 maxArtifactCount;
    /// @notice Min artifact price in the market.
    uint256 minArtifactPrice;
    /// @notice Timestamp of the block that this market parameter was added.
    /// @dev Even if this is provided by the user, it will get overwritten by the internal `block.timestamp`.
    uint256 timestamp;
    /// @notice The maximum fee that a agent agent can charge.
    uint8 maxAgentFee;
}

abstract contract SwanManager is OwnableUpgradeable {
    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Market parameters such as intervals and fees.
    SwanMarketParameters[] marketParameters;
    /// @notice Oracle parameters such as fees.
    LLMOracleTaskParameters oracleParameters;

    /// @notice LLM Oracle Coordinator.
    LLMOracleCoordinator public coordinator;
    /// @notice The token to be used for fee payments.
    ERC20 public token;

    /// @notice Operator addresses that can take actions on behalf of agents,
    /// such as calling `purchase`, or `updateState` for them.
    mapping(address operator => bool) public isOperator;

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
                                  LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the market parameters in memory.
    function getMarketParameters() external view returns (SwanMarketParameters[] memory) {
        return marketParameters;
    }

    /// @notice Returns the oracle parameters in memory.
    function getOracleParameters() external view returns (LLMOracleTaskParameters memory) {
        return oracleParameters;
    }

    /// @notice Pushes a new market parameters to the marketParameters array.
    /// @dev Only callable by owner.
    /// @param _marketParameters new market parameters
    function setMarketParameters(SwanMarketParameters memory _marketParameters) external onlyOwner {
        require(_marketParameters.platformFee <= 100, "Platform fee cannot exceed 100%");
        _marketParameters.timestamp = block.timestamp;
        marketParameters.push(_marketParameters);
    }

    /// @notice Set the oracle parameters.
    /// @dev Only callable by owner.
    /// @param _oracleParameters new oracle parameters
    function setOracleParameters(LLMOracleTaskParameters calldata _oracleParameters) external onlyOwner {
        oracleParameters = _oracleParameters;
    }

    /// @notice Returns the total fee required to make an oracle request.
    /// @dev This is mainly required by the agent to calculate its minimum fund amount, so that it can pay the fee.
    function getOracleFee() external view returns (uint256) {
        (uint256 totalFee,,) = coordinator.getFee(oracleParameters);
        return totalFee;
    }

    /*//////////////////////////////////////////////////////////////
                                OPERATORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds an operator that can take actions on behalf of agents.
    /// @dev Only callable by owner.
    /// @dev Has no effect if the operator is already authorized.
    /// @param _operator new operator address
    function addOperator(address _operator) external onlyOwner {
        isOperator[_operator] = true;
    }

    /// @notice Removes an operator, so that they are no longer authorized.
    /// @dev Only callable by owner.
    /// @dev Has no effect if the operator is already not authorized.
    /// @param _operator operator address to remove
    function removeOperator(address _operator) external onlyOwner {
        delete isOperator[_operator];
    }

    /// @notice Returns the current market parameters.
    /// @dev Current market parameters = Last element in the marketParameters array
    function getCurrentMarketParameters() public view returns (SwanMarketParameters memory) {
        return marketParameters[marketParameters.length - 1];
    }
}
