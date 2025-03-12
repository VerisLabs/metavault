//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console2 } from "forge-std/Script.sol";
import { IMetaVault, ISharePriceOracle } from "interfaces/Lib.sol";
import { ERC7540Engine } from "modules/Lib.sol";
import { AssetsManager } from "modules/Lib.sol";

contract RemoveFunctionsScript is Script {
    IMetaVault public metavault;
    uint256 adminPrivateKey;
    ERC7540Engine public engine;
    AssetsManager public assetsManager;

    function run() public {
        adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        metavault = IMetaVault(vm.envAddress("METAVAULT_ADDRESS"));
        engine = ERC7540Engine(vm.envAddress("ENGINE_ADDRESS"));
        assetsManager = AssetsManager(vm.envAddress("ASSETS_MANAGER_ADDRESS"));
        vm.startBroadcast(adminPrivateKey);

        bytes4[] memory engineSelectors = engine.selectors();
        //bytes4[] memory assetsSelectors = assetsManager.selectors();

        metavault.removeFunctions(engineSelectors);
        //metavault.removeFunctions(assetsSelectors);
        vm.stopBroadcast();
    }
}
