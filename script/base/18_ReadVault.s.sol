//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console2 } from "forge-std/Script.sol";

import { IMetaVault, ISharePriceOracle } from "interfaces/Lib.sol";

contract ReadVaultScript is Script {

    IMetaVault public metavault;

    function run() public {
        metavault = IMetaVault(vm.envAddress("METAVAULT_ADDRESS"));
        metavault.getAllVaultsDetailedData();
    }
}
