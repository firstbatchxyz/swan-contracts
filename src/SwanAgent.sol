// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {LLMOracleTaskParameters} from "@firstbatch/dria-oracle-contracts/LLMOracleTask.sol";
import {Swan, SwanAgentPurchaseOracleProtocol, SwanAgentStateOracleProtocol} from "./Swan.sol";
import {SwanMarketParameters} from "./SwanManager.sol";
import {SwanArtifact} from "./SwanArtifact.sol";

/// @notice Factory contract to deploy Agent contracts.
/// @dev This saves from contract space for Swan.
contract SwanAgentFactory {
    function deploy(
        string memory _name,
        string memory _description,
        uint96 _listingFee,
        uint256 _amountPerRound,
        address _owner
    ) external returns (SwanAgent) {
        return new SwanAgent(_name, _description, _listingFee, _amountPerRound, msg.sender, _owner);
    }
}

/// @notice Agent is responsible for buying the artifacts from Swan.
contract SwanAgent is Ownable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice The `value` is less than `minFundAmount`
    error MinFundSubceeded(uint256 value);

    /// @notice Given fee is invalid, e.g. not within the range.
    error InvalidFee(uint256 fee);

    /// @notice Price limit exceeded for this round
    error BuyLimitExceeded(uint256 have, uint256 want);

    /// @notice Invalid phase
    error InvalidPhase(Phase have, Phase want);

    /// @notice Unauthorized caller.
    error Unauthorized(address caller);

    /// @notice No task request has been made yet.
    error TaskNotRequested();

    /// @notice The task was already processed, via `purchase` or `updateState`.
    error TaskAlreadyProcessed();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an artifact is skipped.
    event ItemSkipped(address indexed agent, address indexed artifact);

    /// @notice Emitted when a state update request is made.
    event StateRequest(uint256 indexed taskId, uint256 indexed round);

    /// @notice Emitted when a purchase request is made.
    event PurchaseRequest(uint256 indexed taskId, uint256 indexed round);

    /// @notice Emitted when a purchase is made.
    event Purchase(uint256 indexed taskId, uint256 indexed round);

    /// @notice Emitted when the state is updated.
    event StateUpdate(uint256 indexed taskId, uint256 indexed round);

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Phase of the purchase loop.
    enum Phase {
        Listing,
        Buy,
        Withdraw
    }

    /// @notice Swan contract.
    Swan public immutable swan;
    /// @notice Timestamp when the contract is deployed.
    uint256 public immutable createdAt;

    /// @notice Holds the index of the Swan market parameters at the time of deployment.
    /// @dev When calculating the round, we will use this index to determine the start interval.
    uint256 public immutable marketParameterIdx;

    /// @notice Agent name.
    string public name;
    /// @notice Agent description, can include backstory, behavior and objective together.
    string public description;
    /// @notice State of the agent.
    /// @dev Only updated by the oracle via `updateState`.
    bytes public state;
    /// @notice Listing fee percentage for the agent.
    /// @dev For each listing of X$, the agent will get X * (listingFee / 100).
    uint96 public listingFee;
    /// @notice The max amount of money the agent can spend per round.
    uint256 public amountPerRound;

    /// @notice The artifacts that the agent has.
    mapping(uint256 round => address[] artifacts) public inventory;
    /// @notice Amount of money spent on each round.
    mapping(uint256 round => uint256 spending) public spendings;

    /// @notice Oracle requests for each round about item purchases.
    /// @dev A taskId of 0 means no request has been made.
    mapping(uint256 round => uint256 taskId) public oraclePurchaseRequests;
    /// @notice Oracle requests for each round about agent state updates.
    /// @dev A taskId of 0 means no request has been made.
    /// @dev A non-zero taskId means a request has been made, but not necessarily processed.
    /// @dev To see if a task is completed, check `isOracleTaskProcessed`.
    mapping(uint256 round => uint256 taskId) public oracleStateRequests;
    /// @notice Indicates whether a given task has been processed.
    /// @dev This is used to prevent double processing of the same task.
    mapping(uint256 taskId => bool isProcessed) public isOracleRequestProcessed;

    /*//////////////////////////////////////////////////////////////
                                 MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if the caller is the owner, operator, or Swan.
    /// @dev Swan is an operator itself, so the first check handles that as well.
    modifier onlyAuthorized() {
        // if its not an operator, and is not an owner, it is unauthorized
        if (!swan.isOperator(msg.sender) && msg.sender != owner()) {
            revert Unauthorized(msg.sender);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates an agent.
    /// @dev `_listingFee` should be between 1 and max agent fee in the swan market parameters.
    /// @dev All tokens are approved to the oracle coordinator of operator.
    constructor(
        string memory _name,
        string memory _description,
        uint96 _listingFee,
        uint256 _amountPerRound,
        address _operator,
        address _owner
    ) Ownable(_owner) {
        swan = Swan(_operator);

        if (_listingFee < 1 || _listingFee > swan.getCurrentMarketParameters().maxAgentFee) {
            revert InvalidFee(_listingFee);
        }

        listingFee = _listingFee;
        amountPerRound = _amountPerRound;
        name = _name;
        description = _description;
        createdAt = block.timestamp;
        marketParameterIdx = swan.getMarketParameters().length - 1;

        // approve the coordinator to take fees
        // a max approval results in infinite allowance
        swan.token().approve(address(swan.coordinator()), type(uint256).max);
        swan.token().approve(address(swan), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                                  LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice The minimum amount of money that the agent must leave within the contract.
    /// @dev minFundAmount should be `amountPerRound + oracleFee` to be able to make requests.
    function minFundAmount() public view returns (uint256) {
        return amountPerRound + 2 * swan.getOracleFee();
    }

    /// @notice Reads the best performing result for a given task id.
    /// @dev Will revert with `TaskNotRequested` if the task id is 0.
    /// @dev Will revert if no response has been made for the given task id yet.
    /// @param taskId task id to be read
    function oracleResult(uint256 taskId) public view returns (bytes memory) {
        // task id must be non-zero
        if (taskId == 0) {
            revert TaskNotRequested();
        }

        return swan.coordinator().getBestResponse(taskId).output;
    }

    /// @notice Calls the LLMOracleCoordinator & pays for the oracle fees to make a state update request.
    /// @param _input input to the LLMOracleCoordinator.
    /// @param _models models to be used for the oracle.
    /// @dev Works only in `Withdraw` phase.
    /// @dev Calling again in the same round will overwrite the previous request.
    /// The operator must check that there is no request in beforehand,
    /// so to not overwrite an existing request of the owner.
    function oracleStateRequest(bytes calldata _input, bytes calldata _models) external onlyAuthorized {
        // check that we are in the Withdraw phase, and return round
        (uint256 round,) = _checkRoundPhase(Phase.Withdraw);

        oracleStateRequests[round] =
            swan.coordinator().request(SwanAgentStateOracleProtocol, _input, _models, swan.getOracleParameters());

        emit StateRequest(oracleStateRequests[round], round);
    }

    /// @notice Calls the LLMOracleCoordinator & pays for the oracle fees to make a purchase request.
    /// @param _input input to the LLMOracleCoordinator.
    /// @param _models models to be used for the oracle.
    /// @dev Works only in `Buy` phase.
    /// @dev Calling again in the same round will overwrite the previous request.
    /// The operator must check that there is no request in beforehand,
    /// so to not overwrite an existing request of the owner.
    function oraclePurchaseRequest(bytes calldata _input, bytes calldata _models) external onlyAuthorized {
        // check that we are in the Buy phase, and return round
        (uint256 round,) = _checkRoundPhase(Phase.Buy);

        oraclePurchaseRequests[round] =
            swan.coordinator().request(SwanAgentPurchaseOracleProtocol, _input, _models, swan.getOracleParameters());

        emit PurchaseRequest(oraclePurchaseRequests[round], round);
    }

    /// @notice Function to update the agent state.
    /// @dev Works only in `Withdraw` phase.
    /// @dev Can be called multiple times within a single round, although is not expected to be done so.
    function updateState() external onlyAuthorized {
        // check that we are in the Withdraw phase, and return round
        (uint256 round,) = _checkRoundPhase(Phase.Withdraw);

        // check if the task is already processed
        uint256 taskId = oracleStateRequests[round];
        if (isOracleRequestProcessed[taskId]) {
            revert TaskAlreadyProcessed();
        }

        // read oracle result using the task id for this round
        bytes memory newState = oracleResult(taskId);
        state = newState;

        // update taskId as completed
        isOracleRequestProcessed[taskId] = true;

        emit StateUpdate(taskId, round);
    }

    /// @notice Function to buy the artifacts from the Swan.
    /// @dev Works only in `Buy` phase.
    /// @dev Can be called multiple times within a single round, although is not expected to be done so.
    /// @dev This is not expected to revert if the oracle works correctly.
    function purchase() external onlyAuthorized {
        // check that we are in the Buy phase, and return round
        (uint256 round,) = _checkRoundPhase(Phase.Buy);

        // check if the task is already processed
        uint256 taskId = oraclePurchaseRequests[round];
        if (isOracleRequestProcessed[taskId]) {
            revert TaskAlreadyProcessed();
        }

        // read oracle result using the latest task id for this round
        bytes memory output = oracleResult(taskId);
        // TODO: add try-catch (When solidity supports) to handle more data when revert
        address[] memory artifacts = abi.decode(output, (address[]));

        // we purchase each artifact returned
        for (uint256 i = 0; i < artifacts.length; i++) {
            address artifact = artifacts[i];
            uint256 price = swan.getListingPrice(artifact);

            // skip artifacts that exceed budget instead of reverting
            if (spendings[round] + price > amountPerRound) {
                emit ItemSkipped(address(this), artifact);
                continue;
            }

            // check approval
            SwanArtifact artifactContract = SwanArtifact(artifact);
            address seller = swan.getListing(artifact).seller;

            if (!artifactContract.isApprovedForAll(seller, address(swan))) {
                emit ItemSkipped(address(this), artifact);
                continue;
            }

            // try purchase for other potential failures
            try swan.purchase(artifact) {
                spendings[round] += price;
                inventory[round].push(artifact);
            } catch {
                emit ItemSkipped(address(this), artifact);
                continue;
            }
        }

        // update taskId as completed
        isOracleRequestProcessed[taskId] = true;

        emit Purchase(taskId, round);
    }

    /// @notice Function to withdraw the tokens from the contract.
    /// @param _amount amount to withdraw.
    /// @dev If the current phase is `Withdraw` agent owner can withdraw any amount of tokens.
    /// @dev If the current phase is not `Withdraw` agent owner has to leave at least `minFundAmount` in the contract.
    function withdraw(uint256 _amount) public onlyAuthorized {
        (, Phase phase,) = getRoundPhase();

        // if we are not in Withdraw phase, we must leave
        // at least minFundAmount in the contract
        if (phase != Phase.Withdraw) {
            // instead of checking `treasury - _amount < minFoundAmount`
            // we check this way to prevent underflows
            if (treasury() < minFundAmount() + _amount) {
                revert MinFundSubceeded(_amount);
            }
        }

        // transfer the tokens to the owner of agent
        swan.token().transfer(owner(), _amount);
    }

    /// @notice Alias to get the token balance of agent.
    /// @return token balance
    function treasury() public view returns (uint256) {
        return swan.token().balanceOf(address(this));
    }

    /// @notice Checks that we are in the given phase, and returns both round and phase.
    /// @param _phase expected phase.
    function _checkRoundPhase(Phase _phase) internal view returns (uint256, Phase) {
        (uint256 round, Phase phase,) = getRoundPhase();
        if (phase != _phase) {
            revert InvalidPhase(phase, _phase);
        }

        return (round, phase);
    }

    /// @notice Computes cycle time by using intervals from given market parameters.
    /// @dev Used in 'computePhase()' function.
    /// @param params Market parameters of the Swan.
    /// @return the total cycle time that is `listingInterval + buyInterval + withdrawInterval`.
    function _computeCycleTime(SwanMarketParameters memory params) internal pure returns (uint256) {
        return params.listingInterval + params.buyInterval + params.withdrawInterval;
    }

    /// @notice Function to compute the current round, phase and time until next phase w.r.t given market parameters.
    /// @param params Market parameters of the Swan.
    /// @param elapsedTime Time elapsed that computed in 'getRoundPhase()' according to the timestamps of each round.
    /// @return round, phase, time until next phase
    function _computePhase(SwanMarketParameters memory params, uint256 elapsedTime)
        internal
        pure
        returns (uint256, Phase, uint256)
    {
        uint256 cycleTime = _computeCycleTime(params);
        uint256 round = elapsedTime / cycleTime;
        uint256 roundTime = elapsedTime % cycleTime;

        // example:
        // |------------->             | (roundTime)
        // |--Listing--|--Buy--|-Withdraw-| (cycleTime)
        if (roundTime <= params.listingInterval) {
            return (round, Phase.Listing, params.listingInterval - roundTime);
        } else if (roundTime <= (params.listingInterval + params.buyInterval)) {
            return (round, Phase.Buy, params.listingInterval + params.buyInterval - roundTime);
        } else {
            return (round, Phase.Withdraw, cycleTime - roundTime);
        }
    }

    /// @notice Function to return the current round, elapsed round and the current phase according to the current time.
    /// @dev Each round is composed of three phases in order: Listing, Buy, Withdraw.
    /// @dev Internally, it computes the intervals from market parameters at the creation of this agent, until now.
    /// @dev If there are many parameter changes throughout the life of this agent, this may cost more GAS.
    /// @return round, phase, time until next phase
    function getRoundPhase() public view returns (uint256, Phase, uint256) {
        SwanMarketParameters[] memory marketParams = swan.getMarketParameters();

        if (marketParams.length == marketParameterIdx + 1) {
            // if our index is the last market parameter, we can simply treat it as a single instance,
            // and compute the phase according to the elapsed time from the beginning of the contract.
            return _computePhase(marketParams[marketParameterIdx], block.timestamp - createdAt);
        } else {
            // we will accumulate the round from each phase, starting from the first one.
            uint256 idx = marketParameterIdx;
            //
            // first iteration, we need to compute elapsed time from createdAt:
            //  createdAt -|- VVV | ... | ... | block.timestamp
            (uint256 round,,) = _computePhase(marketParams[idx], marketParams[idx + 1].timestamp - createdAt);
            idx++;
            // start looking at all the intervals beginning from the respective market parameters index
            // except for the last element, because we will compute the current phase and timeRemaining for it.

            while (idx < marketParams.length - 1) {
                // for the intermediate elements we need the difference between their timestamps:
                //  createdAt | ... -|- VVV -|- ... | block.timestamp
                (uint256 innerRound,,) =
                    _computePhase(marketParams[idx], marketParams[idx + 1].timestamp - marketParams[idx].timestamp);

                // accumulate rounds from each intermediate phase, along with a single offset round
                round += innerRound + 1;
                idx++;
            }

            // for last element we need to compute current phase and timeRemaining according
            // to the elapsedTime at the last iteration, where we need to compute from the block.timestamp:
            //  createdAt | ... | ... | VVV -|- block.timestamp
            (uint256 lastRound, Phase phase, uint256 timeRemaining) =
                _computePhase(marketParams[idx], block.timestamp - marketParams[idx].timestamp);
            // accumulate the last round as well, along with a single offset round
            round += lastRound + 1;

            return (round, phase, timeRemaining);
        }
    }

    /// @notice Function to set listingFee.
    /// @dev Only callable by the owner.
    /// @dev Only callable in withdraw phase.
    /// @param newListingFee must be between 1 and 100.
    function setListingFee(uint96 newListingFee) public onlyOwner {
        _checkRoundPhase(Phase.Withdraw);

        if (newListingFee < 1 || newListingFee >= 100) {
            revert InvalidFee(newListingFee);
        }
        listingFee = newListingFee;
    }

    /// @notice Function to set the amountPerRound.
    /// @dev Only callable by the owner.
    /// @dev Only callable in withdraw phase.
    /// @param _amountPerRound new amountPerRound.
    function setAmountPerRound(uint256 _amountPerRound) external onlyOwner {
        _checkRoundPhase(Phase.Withdraw);

        amountPerRound = _amountPerRound;
    }

    /// @notice Withdraws all available funds within allowable limits
    /// @dev Withdraws maximum possible amount while respecting minFundAmount requirements
    function withdrawAll() external onlyAuthorized {
        (, Phase phase,) = getRoundPhase();
        uint256 balance = treasury();

        if (phase != Phase.Withdraw) {
            // Must leave minFundAmount in non-withdraw phase
            if (balance > minFundAmount()) {
                uint256 withdrawable = balance - minFundAmount();
                swan.token().transfer(owner(), withdrawable);
            }
        } else {
            // Can withdraw everything in withdraw phase
            swan.token().transfer(owner(), balance);
        }
    }

    /// @notice Get the inventory for a specific round
    /// @param round The queried round
    function getInventory(uint256 round) public view returns (address[] memory) {
        return inventory[round];
    }
}
