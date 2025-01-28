//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SuperformGateway } from "crosschain/SuperformGateway/Lib.sol";
import { Script, console2 } from "forge-std/Script.sol";

import { ISuperformGateway } from "interfaces/Lib.sol";

contract SetRecoveryAddress is Script {
    ISuperformGateway public gateway;

    uint256 deployerPrivateKey;
    address superPositionsReceiverAddress;

    function run() public {
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        // same address deployed in every EVM chain
        superPositionsReceiverAddress = 0x0ffAd7aE8ADCA88cdF6FE873Fdf9a0ac2C287BBD;

        vm.startBroadcast(deployerPrivateKey);

        // our deployed SuperformGateway contract
        gateway = ISuperformGateway(0xEd552f8e7Face613d720f97DAbCDA5d6448F6184);
        gateway.setRecoveryAddress(superPositionsReceiverAddress);

        vm.stopBroadcast();
    }
}
