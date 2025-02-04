// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract UpgradeSwan is Script {
    HelperConfig public config;

    function run() external returns (address impl) {
        config = new HelperConfig();
        (address proxy,) = config.getSwanAddresses();

        vm.startBroadcast();
        impl = upgrade(proxy);
        vm.stopBroadcast();
    }

    function upgrade(address proxy) public returns (address impl) {
        require(proxy != address(0), "Invalid proxy address");

        Upgrades.upgradeProxy(proxy, "SwanV2.sol", "");
        impl = Upgrades.getImplementationAddress(proxy);
    }
}
