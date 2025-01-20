//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console2 } from "forge-std/Script.sol";
import { IMetaVault, ISharePriceOracle } from "interfaces/Lib.sol";
import { ERC7540Engine } from "modules/Lib.sol";
import { AssetsManager } from "modules/Lib.sol";

contract AddFunctionsScript is Script {
    IMetaVault public metavault;
    uint256 adminPrivateKey;
    ERC7540Engine public engine;
    AssetsManager public assetsManager;
    
    function run() public {
        adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        metavault = IMetaVault(vm.envAddress("METAVAULT_ADDRESS"));
        vm.startBroadcast(adminPrivateKey);
        
        engine = new ERC7540Engine();
        assetsManager = new AssetsManager();

        bytes4[] memory engineSelectors = engine.selectors();
        bytes4[] memory assetsSelectors = assetsManager.selectors();

        metavault.addFunctions(engineSelectors, address(engine), false);
        metavault.addFunctions(assetsSelectors, address(assetsManager), false);

        console2.log("ERC7540Engine address: ", address(engine));
        console2.log("AssetsManager address: ", address(assetsManager));

        vm.stopBroadcast();
    }
}
