//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console2 } from "forge-std/Script.sol";
import { IMetaVault, ISharePriceOracle } from "interfaces/Lib.sol";

/**
 * @title AddVaultScript
 * @notice Script for adding a new vault to MetaVault
 * @dev Can be run using CLI parameters or environment variables
 *
 * Environment Variables:
 * - ADMIN_PRIVATE_KEY: Private key for deployment
 * - METAVAULT_ADDRESS: Address of the MetaVault contract
 * - CHAIN_ID: Chain ID where the vault is deployed
 * - NEW_VAULT_ADDRESS: Address of the vault to add
 * - SUPERFORM_ID: SuperForm ID of the vault
 * - VAULT_DECIMALS: Decimals of the vault token
 * - SHARE_PRICE_ORACLE_ADDRESS: Address of the share price oracle
 *
 * CLI Usage:
 * forge script script/base/02_AddVault.s.sol --sig "runWithParams(address,uint32,address,uint256,uint8,address)" \
 *   $METAVAULT_ADDRESS $CHAIN_ID $NEW_VAULT_ADDRESS $SUPERFORM_ID $VAULT_DECIMALS $SHARE_PRICE_ORACLE_ADDRESS \
 *   --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY --broadcast
 */
contract AddVaultScript is Script {
    // Script state variables
    IMetaVault public metavault;
    uint32 public chainId;
    uint256 public superformId;
    address public vault;
    uint8 public vaultDecimals;
    ISharePriceOracle public oracle;
    uint256 public deployerPrivateKey;

    // Script flags
    bool private parametersLoaded = false;

    /**
     * @notice Default run function using environment variables
     */
    function run() public {
        console2.log("\n=======================================================");
        console2.log("            ADDING VAULT TO METAVAULT");
        console2.log("=======================================================\n");

        console2.log("[INFO] Loading parameters from environment variables...");

        try this.loadFromEnv() {
            console2.log("[SUCCESS] Successfully loaded all parameters from environment variables");
        } catch Error(string memory reason) {
            console2.log("[ERROR] Failed to load parameters:", reason);
            console2.log("\n[HINT] You can also run with direct parameters using:");
            console2.log(
                "forge script script/base/02_AddVault.s.sol --sig \"runWithParams(address,uint32,address,uint256,uint8,address)\" \\"
            );
            console2.log(
                "  $METAVAULT_ADDRESS $CHAIN_ID $NEW_VAULT_ADDRESS $SUPERFORM_ID $VAULT_DECIMALS $SHARE_PRICE_ORACLE_ADDRESS \\"
            );
            console2.log("  --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY --broadcast");
            return;
        }

        executeAddVault();
    }

    /**
     * @notice Run function with direct parameters
     * @param _metavault Address of the MetaVault contract
     * @param _chainId Chain ID where the vault is deployed
     * @param _vault Address of the vault to add
     * @param _superformId SuperForm ID of the vault
     * @param _vaultDecimals Decimals of the vault token
     * @param _oracle Address of the share price oracle
     */
    function runWithParams(
        address _metavault,
        uint32 _chainId,
        address _vault,
        uint256 _superformId,
        uint8 _vaultDecimals,
        address _oracle
    )
        public
    {
        console2.log("\n=======================================================");
        console2.log("            ADDING VAULT TO METAVAULT");
        console2.log("=======================================================\n");

        console2.log("[INFO] Using directly provided parameters");

        // Still need private key from environment
        try vm.envUint("ADMIN_PRIVATE_KEY") returns (uint256 key) {
            deployerPrivateKey = key;
            console2.log("[SUCCESS] Loaded ADMIN_PRIVATE_KEY from environment variables");
        } catch {
            console2.log("[ERROR] Failed to load ADMIN_PRIVATE_KEY from environment");
            console2.log("ADMIN_PRIVATE_KEY environment variable is required even when using direct parameters");
            return;
        }

        metavault = IMetaVault(_metavault);
        chainId = _chainId;
        vault = _vault;
        superformId = _superformId;
        vaultDecimals = _vaultDecimals;
        oracle = ISharePriceOracle(_oracle);

        parametersLoaded = true;

        executeAddVault();
    }

    /**
     * @notice Loads parameters from environment variables
     * @dev This is exposed as an external function to allow try/catch in the main run function
     */
    function loadFromEnv() external {
        deployerPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        if (deployerPrivateKey == 0) revert("ADMIN_PRIVATE_KEY not set or invalid");

        chainId = uint32(vm.envUint("CHAIN_ID"));
        if (chainId == 0) revert("CHAIN_ID not set or invalid");

        address vaultAddress = vm.envAddress("NEW_VAULT_ADDRESS");
        if (vaultAddress == address(0)) revert("NEW_VAULT_ADDRESS not set or invalid");
        vault = vaultAddress;

        uint256 sfId = vm.envUint("SUPERFORM_ID");
        if (sfId == 0) revert("SUPERFORM_ID not set or invalid");
        superformId = sfId;

        address mvAddress = vm.envAddress("METAVAULT_ADDRESS");
        if (mvAddress == address(0)) revert("METAVAULT_ADDRESS not set or invalid");
        metavault = IMetaVault(mvAddress);

        vaultDecimals = uint8(vm.envUint("VAULT_DECIMALS"));
        if (vaultDecimals == 0) {
            console2.log("[WARNING] VAULT_DECIMALS is set to 0. Make sure this is correct!");
        }

        address oracleAddress = vm.envAddress("SHARE_PRICE_ORACLE_ADDRESS");
        if (oracleAddress == address(0)) revert("SHARE_PRICE_ORACLE_ADDRESS not set or invalid");
        oracle = ISharePriceOracle(oracleAddress);

        parametersLoaded = true;
    }

    /**
     * @notice Executes the addVault transaction
     */
    function executeAddVault() private {
        if (!parametersLoaded) {
            console2.log("[ERROR] Cannot execute: parameters not loaded");
            return;
        }

        console2.log("\n[PARAMETERS] Add Vault Parameters:");
        console2.log(" - MetaVault Address:", address(metavault));
        console2.log(" - Chain ID:", chainId);
        console2.log(" - Vault Address:", vault);
        console2.log(" - SuperForm ID:", superformId);
        console2.log(" - Vault Decimals:", vaultDecimals);
        console2.log(" - Oracle Address:", address(oracle));
        console2.log(" - Deployer Account:", vm.addr(deployerPrivateKey));

        console2.log("\n[EXECUTING] Executing addVault transaction...");
        vm.startBroadcast(deployerPrivateKey);

        try metavault.addVault(chainId, superformId, vault, vaultDecimals, oracle) {
            console2.log("[SUCCESS] Successfully added vault to MetaVault!");

            // Verify the vault was added by checking if it's listed
            bool isListed = metavault.isVaultListed(vault);
            if (isListed) {
                console2.log("[VERIFIED] Vault confirmed to be listed in MetaVault");
            } else {
                console2.log("[WARNING] Vault not showing as listed in MetaVault. Check for issues.");
            }
        } catch (bytes memory reason) {
            console2.log("[ERROR] Failed to add vault to MetaVault");
            console2.logBytes(reason);
        }

        vm.stopBroadcast();

        console2.log("\n=======================================================");
        console2.log("               OPERATION COMPLETED");
        console2.log("=======================================================");
    }
}
