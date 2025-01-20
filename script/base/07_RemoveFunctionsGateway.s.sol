//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console2 } from "forge-std/Script.sol";
import { SuperformGateway } from "crosschain/SuperformGateway/SuperformGateway.sol";
import {
    DivestSuperform, InvestSuperform, LiquidateSuperform, SuperformGateway
} from "crosschain/SuperformGateway/Lib.sol";
import { SUPERFORM_ROUTER_BASE, SUPERFORM_SUPERPOSITIONS_BASE, USDCE_BASE } from "helpers/AddressBook.sol";
import {
    IBaseRouter,
    ISuperPositions,
    ISuperformGateway
} from "interfaces/Lib.sol";

contract RemoveFunctionsScript is Script {
    uint256 adminPrivateKey;
    ISuperformGateway public gateway;
    InvestSuperform invest;
    DivestSuperform divest;
    LiquidateSuperform liquidate;

    function run() public {
        adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        gateway = ISuperformGateway(payable(vm.envAddress("SUPERFORM_GATEWAY_ADDRESS")));

        vm.startBroadcast(adminPrivateKey);

        invest = InvestSuperform(vm.envAddress("INVEST_ADDRESS"));
        divest = DivestSuperform(vm.envAddress("DIVEST_ADDRESS"));
        liquidate = LiquidateSuperform(vm.envAddress("LIQUIDATE_ADDRESS"));

        bytes4[] memory investSelectors = invest.selectors();
        bytes4[] memory divestSelectors = divest.selectors();
        bytes4[] memory liquidateSelectors = liquidate.selectors();

        gateway.removeFunctions(investSelectors);
        gateway.removeFunctions(divestSelectors);
        gateway.removeFunctions(liquidateSelectors);

        vm.stopBroadcast();
    }
}
