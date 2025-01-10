//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    SuperformGateway
} from "crosschain/SuperformGateway/Lib.sol";
import { Script, console2 } from "forge-std/Script.sol";

import {
    ISuperformGateway
} from "interfaces/Lib.sol";

contract SetRecoveryAddress is Script {
    ISuperformGateway public gateway;

    uint256 deployerPrivateKey;
    address superPositionsReceiverAddress;

    function run() public {
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        // same address deployed in every EVM chain 
        superPositionsReceiverAddress = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        
        vm.startBroadcast(deployerPrivateKey);
        
        // our deployed SuperformGateway contract
        gateway = ISuperformGateway(0x3228F64baE214d2562FaE387b5456BE10385648A); 
        gateway.setRecoveryAddress(superPositionsReceiverAddress);
        
        vm.stopBroadcast();
    }
}
