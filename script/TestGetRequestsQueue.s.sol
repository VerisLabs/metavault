//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script, console2 } from "forge-std/Script.sol";
import { ISuperformGateway } from "interfaces/Lib.sol";

contract TestGetRequestsQueue is Script {
    ISuperformGateway public gateway;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("RELAYER_PRIVATE_KEY");
        address gatewayAddress = vm.envAddress("SUPERFORM_GATEWAY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);
        gateway = ISuperformGateway(gatewayAddress);

        // Get the requests queue
        bytes32[] memory requestIds = gateway.getRequestsQueue();

        // Log the results
        console2.log("Number of pending requests:", requestIds.length);
        for (uint256 i = 0; i < requestIds.length; i++) {
            console2.log("Request ID:", uint256(requestIds[i]));
        }

        vm.stopBroadcast();
    }
} 