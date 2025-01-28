//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SuperPositionsReceiver } from "crosschain/SuperPositionsReceiver.sol";
import { Script, console2 } from "forge-std/Script.sol";

contract SetGateway is Script {
    SuperPositionsReceiver public receiver;

    uint256 deployerPrivateKey;
    address gatewayAddress;

    function run() public {
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        gatewayAddress = 0x7c0a54980C9CA702308688014fda0E8016e6c1F9;

        vm.startBroadcast(deployerPrivateKey);

        receiver = SuperPositionsReceiver(0xd734735784aEE9D66FB7314469c7aF9972A7F735);
        receiver.setGateway(gatewayAddress);

        vm.stopBroadcast();
    }
}
