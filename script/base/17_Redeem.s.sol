//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SuperformGateway } from "crosschain/SuperformGateway/Lib.sol";
import { Script, console2 } from "forge-std/Script.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import { IMetaVault } from "interfaces/Lib.sol";

contract RedeemScript is Script, StdCheats {
    IMetaVault public vault;

    address vaultAddress;
    address constant callerAddress = 0x80DB09D92E234B1B2EE6ed40BB729DF3B27e2F60;

    function run() public {
        deal(callerAddress, 100 ether);
        vm.startPrank(callerAddress);
        vaultAddress = vm.envAddress("VAULT_ADDRESS");

        vault = IMetaVault(vaultAddress);
        vault.redeem(199767791914335,callerAddress, callerAddress);
    }
}
