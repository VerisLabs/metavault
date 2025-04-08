//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console2 } from "forge-std/Script.sol";
import { IMetaVault } from "interfaces/Lib.sol";
import { MetaVaultReader } from "src/modules/MetaVaultReader.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { ISharePriceOracle } from "src/interfaces/ISharePriceOracle.sol";

contract TestVaultDataScript is Script, StdCheats {
    IMetaVault public vault;
    MetaVaultReader public reader;
    uint256 deployerPrivateKey;
    address deployer;
    address constant callerAddress = 0x80DB09D92E234B1B2EE6ed40BB729DF3B27e2F60;

    // Define the structs locally to avoid type resolution issues
    struct VaultDetailedData {
        uint32 chainId;
        uint256 superformId;
        ISharePriceOracle oracle;
        uint8 decimals;
        uint128 totalDebt;
        address vaultAddress;
        uint256 sharesBalance;
        uint256 sharePrice;
        uint256 totalAssets;
    }

    struct VaultReturnsData {
        uint256 totalReturn;
        uint256 hurdleReturn;
        uint256 excessReturn;
    }

    function run() public {
        console2.log("=======================================================");
        console2.log("            STARTING VAULT DATA TEST");
        console2.log("=======================================================");

        // Load environment variables
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        
        // Load vault address from environment
        address vaultAddress = vm.envAddress("METAVAULT_ADDRESS");
        
        console2.log("Deployer address:", deployer);
        console2.log("Vault address:", vaultAddress);
        
        // Start prank as caller address
        vm.startPrank(callerAddress);
        
        // Create reader instance
        reader = MetaVaultReader(vaultAddress);
        
        // Get all vaults data
        console2.log("Getting all vaults data...");
        VaultDetailedData[] memory allVaults = reader.getAllVaultsDetailedData();
        
        // Print data for each vault
        for (uint256 i = 0; i < allVaults.length; i++) {
            console2.log("-------------------------------------------------------");
            console2.log("Vault #", i + 1);
            console2.log("Chain ID:", allVaults[i].chainId);
            console2.log("Superform ID:", allVaults[i].superformId);
            console2.log("Vault Address:", allVaults[i].vaultAddress);
            console2.log("Decimals:", allVaults[i].decimals);
            console2.log("Total Debt:", allVaults[i].totalDebt);
            console2.log("Shares Balance:", allVaults[i].sharesBalance);
            console2.log("Share Price:", allVaults[i].sharePrice);
            console2.log("Total Assets:", allVaults[i].totalAssets);
        }
        
        // Get returns data
        console2.log("-------------------------------------------------------");
        console2.log("Getting vault returns data...");
        VaultReturnsData memory returnsData = reader.getLastEpochVaultReturns();
        console2.log("Total Return:", returnsData.totalReturn);
        console2.log("Hurdle Return:", returnsData.hurdleReturn);
        console2.log("Excess Return:", returnsData.excessReturn);
        
        // Get total returns per share
        console2.log("-------------------------------------------------------");
        console2.log("Getting total returns per share...");
        int256 totalReturns = reader.totalReturnsPerShare();
        console2.log("Total Returns Per Share:", totalReturns);
        
        vm.stopPrank();
        
        console2.log("=======================================================");
        console2.log("            VAULT DATA TEST COMPLETE");
        console2.log("=======================================================");
    }
} 