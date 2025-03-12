//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console2 } from "forge-std/Script.sol";
import { IMetaVault, ISharePriceOracle } from "interfaces/Lib.sol";
import { IERC20 } from "interfaces/IERC20.sol";

contract OperatorScript is Script {
    IMetaVault public metavault;
    uint256 deployerPrivateKey;
    uint256 relayerPrivateKey;
    address owner;
    address executor;

    function run() public {
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        relayerPrivateKey = vm.envUint("RELAYER_PRIVATE_KEY");
        metavault = IMetaVault(vm.envAddress("METAVAULT_ADDRESS"));
        owner = 0x429796dAc057E7C15724196367007F1e9Cff82F9;
        executor = 0x88190A6F759CF1115e0c6BCF4Eea1Fef0994e873;
        vm.startBroadcast(deployerPrivateKey);

        metavault.setOperator(0x88190A6F759CF1115e0c6BCF4Eea1Fef0994e873, true);
        IERC20(metavault.asset()).approve(executor, 1000000);
        IERC20(metavault.asset()).transfer(executor, 1000000);
        
        vm.stopBroadcast();
        vm.startBroadcast(relayerPrivateKey);
        
        IERC20(metavault.asset()).approve(address(metavault), 1000000);
        metavault.requestDeposit(1000000, owner, executor);
        metavault.deposit(1000000, owner, owner);
        vm.stopBroadcast();
    }
}
