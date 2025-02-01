//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { SuperPositionsReceiver } from "../../src/crosschain/SuperPositionsReceiver.sol";
import "forge-std/Script.sol";

contract DeploySuperPositionsReceiver is Script {
    uint256 adminPrivateKey;

    function run() external {
        adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        address GATEWAY = 0xEd552f8e7Face613d720f97DAbCDA5d6448F6184;
        address SUPERPOSITIONS = 0x01dF6fb6a28a89d6bFa53b2b3F20644AbF417678;
        address OWNER = 0x429796dAc057E7C15724196367007F1e9Cff82F9;

        // Generate bytecode + constructor args dynamically
        bytes memory bytecode = abi.encodePacked(
            type(SuperPositionsReceiver).creationCode,
            abi.encode(8453, GATEWAY, SUPERPOSITIONS, OWNER)
        );

        vm.startBroadcast(adminPrivateKey);

        bytes32 salt = keccak256(abi.encode(8453, GATEWAY, SUPERPOSITIONS, OWNER));

        (bool success,) = CREATE2_DEPLOYER.call(abi.encodePacked(salt, bytecode));
        require(success, "deployment failed");
        vm.stopBroadcast();
    }
}
