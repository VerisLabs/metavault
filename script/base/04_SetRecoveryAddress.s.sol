//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SuperformGateway } from "crosschain/SuperformGateway/Lib.sol";
import { Script, console2 } from "forge-std/Script.sol";

import { ISuperformGateway } from "interfaces/Lib.sol";

contract SetRecoveryAddress is Script {
    ISuperformGateway public gateway;

    uint256 deployerPrivateKey;
    address gatewayAddress;
    address superPositionsReceiverAddress;

    function run() public {
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        gatewayAddress = vm.envAddress("SUPERFORM_GATEWAY_ADDRESS");
        // same address deployed in every EVM chain
        superPositionsReceiverAddress = vm.envAddress("SUPER_POSITIONS_RECEIVER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // our deployed SuperformGateway contract
        gateway = ISuperformGateway(gatewayAddress);
        gateway.setRecoveryAddress(superPositionsReceiverAddress);

        vm.stopBroadcast();
    }
}
