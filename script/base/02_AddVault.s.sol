//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console2 } from "forge-std/Script.sol";
import { IMetaVault, ISharePriceOracle } from "interfaces/Lib.sol";

contract AddVaultScript is Script {
    IMetaVault public metavault;
    uint64 chainId;
    uint256 superformId;
    address vault;
    uint8 vaultDecimals;
    uint16 deductedFees;
    ISharePriceOracle oracle;
    uint256 deployerPrivateKey;

    function run() public {
        deployerPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        chainId = uint64(vm.envUint("CHAIN_ID"));
        vault = vm.envAddress("NEW_VAULT_ADDRESS");
        superformId = vm.envUint("SUPERFORM_ID");
        metavault = IMetaVault(vm.envAddress("METAVAULT_ADDRESS"));
        vaultDecimals = uint8(vm.envUint("VAULT_DECIMALS"));
        deductedFees = uint16(vm.envUint("DEDUCTED_FEES"));
        oracle = ISharePriceOracle(vm.envAddress("SHARE_PRICE_ORACLE_ADDRESS"));
        vm.startBroadcast(deployerPrivateKey);

        metavault.addVault(chainId, superformId, vault, vaultDecimals, deductedFees, oracle);
        vm.stopBroadcast();
    }
}
