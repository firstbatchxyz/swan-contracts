// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Script} from "forge-std/Script.sol";

import {LLMOracleTaskParameters} from "@firstbatch/dria-oracle-contracts/LLMOracleTask.sol";
import {SwanMarketParameters} from "../src/SwanManager.sol";
import {LLMOracleCoordinator} from "@firstbatch/dria-oracle-contracts/LLMOracleCoordinator.sol";
import {LLMOracleRegistry} from "@firstbatch/dria-oracle-contracts/LLMOracleRegistry.sol";
import {SwanAgentFactory} from "../src/SwanAgent.sol";
import {SwanArtifactFactory} from "../src/SwanArtifact.sol";
import {Swan} from "../src/Swan.sol";
import {SwanLottery} from "../src/SwanLottery.sol";
import {SwanDebate} from "../src/SwanDebate.sol";
import {WETH9} from "../test/contracts/WETH9.sol";

struct Stakes {
    uint256 generatorStakeAmount;
    uint256 validatorStakeAmount;
}

struct Fees {
    uint256 platformFee;
    uint256 generationFee;
    uint256 validationFee;
}

contract HelperConfig is Script {
    LLMOracleTaskParameters public taskParams;
    SwanMarketParameters public marketParams;

    Stakes public stakes;
    Fees public fees;
    WETH9 public token;

    uint256 public minRegistrationTime; // in seconds
    uint256 public minScore;
    uint256 public maxScore;

    constructor() {
        // set deployment parameters
        stakes = Stakes({generatorStakeAmount: 0.0001 ether, validatorStakeAmount: 0.000001 ether});
        fees = Fees({platformFee: 0.0001 ether, generationFee: 0.0001 ether, validationFee: 0.0001 ether});
        taskParams = LLMOracleTaskParameters({difficulty: 2, numGenerations: 1, numValidations: 1});

        marketParams = SwanMarketParameters({
            maxArtifactCount: 750,
            listingInterval: 4 hours,
            buyInterval: 30 minutes,
            withdrawInterval: 15 minutes,
            platformFee: 15, // percentage
            minArtifactPrice: 0.00001 ether,
            timestamp: 0, // will be set in the first call
            maxAgentFee: 75 // percentage
        });

        minRegistrationTime = 1 days;
        maxScore = type(uint8).max; // 255
        minScore = 1;

        token = WETH9(payable(0x4200000000000000000000000000000000000006));
    }

    function deployLLMOracleRegistry() external returns (address proxy, address impl) {
        vm.startBroadcast();

        // deploy llm contracts
        address registryProxy = Upgrades.deployUUPSProxy(
            "LLMOracleRegistry.sol",
            abi.encodeCall(
                LLMOracleRegistry.initialize,
                (stakes.generatorStakeAmount, stakes.validatorStakeAmount, address(token), minRegistrationTime)
            )
        );

        address registryImplementation = Upgrades.getImplementationAddress(registryProxy);
        vm.stopBroadcast();

        writeProxyAddresses("LLMOracleRegistry", registryProxy, registryImplementation);

        return (registryProxy, registryImplementation);
    }

    function deployLLMOracleCoordinator() external returns (address proxy, address impl) {
        // get the registry proxy address from chainid.json file under the deployment dir
        string memory dir = "deployments/";
        string memory fileName = Strings.toString(block.chainid);
        string memory path = string.concat(dir, fileName, ".json");

        string memory contractAddresses = vm.readFile(path);
        bool isRegistryExist = vm.keyExistsJson(contractAddresses, "$.LLMOracleRegistry");
        require(isRegistryExist, "Please deploy LLMOracleRegistry first");

        address registryProxy = vm.parseJsonAddress(contractAddresses, "$.LLMOracleRegistry.proxyAddr");
        require(registryProxy != address(0), "LLMOracleRegistry proxy address is invalid");

        address registryImlp = vm.parseJsonAddress(contractAddresses, "$.LLMOracleRegistry.implAddr");
        require(registryImlp != address(0), "LLMOracleRegistry implementation address is invalid");

        vm.startBroadcast();
        // deploy coordinator contract
        address coordinatorProxy = Upgrades.deployUUPSProxy(
            "LLMOracleCoordinator.sol",
            abi.encodeCall(
                LLMOracleCoordinator.initialize,
                (
                    registryProxy,
                    address(token),
                    fees.platformFee,
                    fees.generationFee,
                    fees.validationFee,
                    minScore,
                    maxScore
                )
            )
        );

        address coordinatorImplementation = Upgrades.getImplementationAddress(coordinatorProxy);

        vm.stopBroadcast();
        writeProxyAddresses("LLMOracleCoordinator", coordinatorProxy, coordinatorImplementation);

        return (coordinatorProxy, coordinatorImplementation);
    }

    function deployAgentFactory() external returns (address) {
        vm.startBroadcast();
        SwanAgentFactory agentFactory = new SwanAgentFactory();
        vm.stopBroadcast();

        writeContractAddress("SwanAgentFactory", address(agentFactory));

        return address(agentFactory);
    }

    function deployArtifactFactory() external returns (address) {
        vm.startBroadcast();
        SwanArtifactFactory artifactFactory = new SwanArtifactFactory();
        vm.stopBroadcast();

        writeContractAddress("SwanArtifactFactory", address(artifactFactory));

        return address(artifactFactory);
    }

    function deploySwan() external returns (address proxy, address impl) {
        // read deployed contract addresses
        string memory dir = "deployments/";
        string memory fileName = Strings.toString(block.chainid);
        string memory path = string.concat(dir, fileName, ".json");

        string memory contractAddresses = vm.readFile(path);

        bool isCoordinatorExist = vm.keyExistsJson(contractAddresses, "$.LLMOracleCoordinator");
        bool isAgentFactoryExist = vm.keyExistsJson(contractAddresses, "$.SwanAgentFactory");
        bool isArtifactFactoryExist = vm.keyExistsJson(contractAddresses, "$.SwanArtifactFactory");

        require(
            isCoordinatorExist && isAgentFactoryExist && isArtifactFactoryExist,
            "Please deploy LLMOracleCoordinator, SwanAgentFactory and SwanArtifactFactory first"
        );

        address coordinatorProxy = vm.parseJsonAddress(contractAddresses, "$.LLMOracleCoordinator.proxyAddr");
        address agentFactory = vm.parseJsonAddress(contractAddresses, "$.SwanAgentFactory.addr");
        address artifactFactory = vm.parseJsonAddress(contractAddresses, "$.SwanArtifactFactory.addr");

        vm.startBroadcast();
        // deploy swan
        address swanProxy = Upgrades.deployUUPSProxy(
            "Swan.sol",
            abi.encodeCall(
                Swan.initialize,
                (
                    SwanMarketParameters(
                        marketParams.withdrawInterval,
                        marketParams.listingInterval,
                        marketParams.buyInterval,
                        marketParams.platformFee,
                        marketParams.maxArtifactCount,
                        marketParams.minArtifactPrice,
                        block.timestamp,
                        marketParams.maxAgentFee
                    ),
                    LLMOracleTaskParameters(taskParams.difficulty, taskParams.numGenerations, taskParams.numValidations),
                    coordinatorProxy,
                    address(token),
                    agentFactory,
                    artifactFactory
                )
            )
        );

        address swanImplementation = Upgrades.getImplementationAddress(swanProxy);
        vm.stopBroadcast();
        writeProxyAddresses("Swan", swanProxy, swanImplementation);

        return (swanProxy, swanImplementation);
    }

    function deploySwanImpl() external returns (address impl) {
        vm.startBroadcast();
        Swan newImplementation = new Swan();
        vm.stopBroadcast();

        // console.log("New implementation address:", address(newImplementation));
        return address(newImplementation);
    }

    function deploySwanLottery() external returns (address) {
        // read Swan proxy address from deployments file
        string memory dir = "deployments/";
        string memory fileName = Strings.toString(block.chainid);
        string memory path = string.concat(dir, fileName, ".json");

        string memory contractAddresses = vm.readFile(path);
        bool isSwanExist = vm.keyExistsJson(contractAddresses, "$.Swan");
        require(isSwanExist, "Please deploy Swan first");

        address swanProxy = vm.parseJsonAddress(contractAddresses, "$.Swan.proxyAddr");
        require(swanProxy != address(0), "Swan proxy address is invalid");

        // Default claim window
        uint256 defaultClaimWindow = 2;

        vm.startBroadcast();
        SwanLottery lottery = new SwanLottery(swanProxy, defaultClaimWindow);
        vm.stopBroadcast();

        writeContractAddress("SwanLottery", address(lottery));

        return address(lottery);
    }

    function deploySwanDebate() external returns (address) {
        // read deployed contract addresses
        string memory dir = "deployments/";
        string memory fileName = Strings.toString(block.chainid);
        string memory path = string.concat(dir, fileName, ".json");
        string memory contractAddresses = vm.readFile(path);

        bool isCoordinatorExist = vm.keyExistsJson(contractAddresses, "$.LLMOracleCoordinator");
        require(isCoordinatorExist, "Please deploy LLMOracleCoordinator first");

        address coordinatorProxy = vm.parseJsonAddress(contractAddresses, "$.LLMOracleCoordinator.proxyAddr");
        require(coordinatorProxy != address(0), "Coordinator proxy address is invalid");

        vm.startBroadcast();
        SwanDebate debate = new SwanDebate(coordinatorProxy);
        vm.stopBroadcast();

        writeContractAddress("SwanDebate", address(debate));
        return address(debate);
    }

    function writeContractAddress(string memory name, address addr) internal {
        // create a deployment file if not exist
        string memory dir = "deployments/";
        string memory fileName = Strings.toString(block.chainid);
        string memory path = string.concat(dir, fileName, ".json");

        // create dir if it doesn't exist
        vm.createDir(dir, true);

        // create file if it doesn't exist
        if (!vm.isFile(path)) {
            vm.writeFile(path, "");
        }

        // check if the key exists
        string memory contractAddresses = vm.readFile(path);

        string memory addrStr = Strings.toHexString(uint256(uint160(addr)), 20);

        // create a new JSON object
        string memory newContract = string.concat('"', name, '": {', ' "addr": "', addrStr, '"', "}");
        if (bytes(contractAddresses).length == 0) {
            // write the new contract to the file
            vm.writeJson(string.concat("{", newContract, "}"), path);
        } else {
            bool isExist = vm.keyExistsJson(contractAddresses, string.concat("$.", name));

            if (isExist) {
                // update values
                vm.writeJson(addrStr, path, string.concat("$.", name, ".addr"));
            } else {
                // Remove the last character '}' from the existing JSON string
                bytes memory contractBytes = bytes(contractAddresses);
                contractBytes[contractBytes.length - 1] = bytes1(",");

                // Append the new contract object and close the JSON
                string memory updatedContracts = string.concat(contractAddresses, newContract, "}");
                // write the updated JSON to the file
                vm.writeJson(updatedContracts, path);
            }
        }
    }

    function writeProxyAddresses(string memory name, address proxy, address impl) internal {
        // create a deployment file if not exist
        string memory dir = "deployments/";
        string memory fileName = Strings.toString(block.chainid);
        string memory path = string.concat(dir, fileName, ".json");

        string memory proxyAddr = Strings.toHexString(uint256(uint160(proxy)), 20);
        string memory implAddr = Strings.toHexString(uint256(uint160(impl)), 20);

        // create dir if it doesn't exist
        vm.createDir(dir, true);

        // create file if it doesn't exist
        if (!vm.isFile(path)) {
            vm.writeFile(path, "");
        }

        // create a new JSON object
        string memory newContract =
            string.concat('"', name, '": {', '  "proxyAddr": "', proxyAddr, '",', '  "implAddr": "', implAddr, '"', "}");

        // read file content
        string memory contractAddresses = vm.readFile(path);

        // if the file is not empty, check key exists
        if (bytes(contractAddresses).length == 0) {
            // write the new contract to the file
            vm.writeJson(string.concat("{", newContract, "}"), path);
        } else {
            // check if the key exists
            bool isExist = vm.keyExistsJson(contractAddresses, string.concat("$.", name));

            if (isExist) {
                // update values
                vm.writeJson(proxyAddr, path, string.concat("$.", name, ".proxyAddr"));
                vm.writeJson(implAddr, path, string.concat("$.", name, ".implAddr"));
            } else {
                // Remove the last character '}' from the existing JSON string
                bytes memory contractBytes = bytes(contractAddresses);
                contractBytes[contractBytes.length - 1] = bytes1(",");

                // Append the new contract object and close the JSON
                string memory updatedContracts = string.concat(contractAddresses, newContract, "}");
                // write the updated JSON to the file
                vm.writeJson(updatedContracts, path);
            }
        }
    }

    function getSwanAddresses() public view returns (address proxy, address impl) {
        string memory path = string.concat("deployments/", Strings.toString(block.chainid), ".json");
        string memory contractAddresses = vm.readFile(path);

        require(vm.keyExistsJson(contractAddresses, "$.Swan"), "Swan not deployed");
        proxy = vm.parseJsonAddress(contractAddresses, "$.Swan.proxyAddr");
        impl = vm.parseJsonAddress(contractAddresses, "$.Swan.implAddr");
    }
}
