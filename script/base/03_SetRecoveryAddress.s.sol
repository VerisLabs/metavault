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
        superPositionsReceiverAddress = 0xc80c3A0D2fC0f95626F9612F893D88384B0ABa51;

        vm.startBroadcast(deployerPrivateKey);

        // our deployed SuperformGateway contract
        gateway = ISuperformGateway(0x3B05001859654937d5a0927427D5C7d49178837E);
        gateway.setRecoveryAddress(superPositionsReceiverAddress);

        vm.stopBroadcast();
    }
}
