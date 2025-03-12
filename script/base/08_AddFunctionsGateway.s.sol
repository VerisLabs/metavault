//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    DivestSuperform, InvestSuperform, LiquidateSuperform, SuperformGateway
} from "crosschain/SuperformGateway/Lib.sol";
import { SuperformGateway } from "crosschain/SuperformGateway/SuperformGateway.sol";
import { Script, console2 } from "forge-std/Script.sol";

import { SUPERFORM_ROUTER_BASE, SUPERFORM_SUPERPOSITIONS_BASE, USDCE_BASE } from "helpers/AddressBook.sol";
import { IBaseRouter, ISuperPositions, ISuperformGateway } from "interfaces/Lib.sol";

contract AddFunctionsScript is Script {
    uint256 adminPrivateKey;
    ISuperformGateway public gateway;

    function run() public {
        adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        gateway = ISuperformGateway(payable(vm.envAddress("SUPERFORM_GATEWAY_ADDRESS")));

        vm.startBroadcast(adminPrivateKey);

        InvestSuperform invest = new InvestSuperform();
        DivestSuperform divest = new DivestSuperform();
        LiquidateSuperform liquidate = new LiquidateSuperform();

        bytes4[] memory investSelectors = invest.selectors();
        bytes4[] memory divestSelectors = divest.selectors();
        bytes4[] memory liquidateSelectors = liquidate.selectors();

        gateway.addFunctions(investSelectors, address(invest), false);
        gateway.addFunctions(divestSelectors, address(divest), false);
        gateway.addFunctions(liquidateSelectors, address(liquidate), false);

        console2.log("InvestSuperform address: ", address(invest));
        console2.log("DivestSuperform address: ", address(divest));
        console2.log("LiquidateSuperform address: ", address(liquidate));

        vm.stopBroadcast();
    }
}
