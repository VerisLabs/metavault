//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console2 } from "forge-std/Script.sol";
import { IMetaVault } from "interfaces/Lib.sol";
import {
    AssetsManager,
    ERC7540Engine,
    ERC7540EngineReader,
    ERC7540EngineSignatures,
    EmergencyAssetsManager,
    MetaVaultReader
} from "modules/Lib.sol";

/**
 * @title RemoveFunctionsScript
 * @notice Script for removing function selectors from MetaVault modules
 * @dev Can use CLI parameters or environment variables to specify which module's functions to remove
 *
 * Environment Variables:
 * - ADMIN_PRIVATE_KEY: Private key for the admin account
 * - METAVAULT_ADDRESS: Address of the MetaVault contract
 * - MODULE_ADDRESS: Address of the module whose functions to remove
 * - MODULE_TYPE: (Optional) Type of module to remove functions from (engine, assetsManager, etc.)
 *
 * CLI Usage:
 * forge script script/base/05_RemoveFunctions.s.sol --sig "runWithParams(address,address,string)" \
 *   $METAVAULT_ADDRESS $MODULE_ADDRESS "engine" \
 *   --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY --broadcast
 */
contract RemoveFunctionsScript is Script {
    IMetaVault public metavault;
    uint256 private adminPrivateKey;
    address private moduleAddress;
    string private moduleType;
    bool private parametersLoaded = false;

    // Known module types
    string[] private knownModuleTypes =
        ["engine", "engineReader", "engineSignatures", "assetsManager", "metaVaultReader", "emergencyAssetsManager"];

    /**
     * @notice Default run function using environment variables
     */
    function run() public {
        console2.log("\n=======================================================");
        console2.log("        REMOVING FUNCTIONS FROM METAVAULT");
        console2.log("=======================================================\n");

        console2.log("[INFO] Loading parameters from environment variables...");

        try this.loadFromEnv() {
            console2.log("[SUCCESS] Successfully loaded all parameters from environment variables");
        } catch Error(string memory reason) {
            console2.log("[ERROR] Failed to load parameters:", reason);
            console2.log("\n[HINT] You can also run with direct parameters using:");
            console2.log(
                "forge script script/base/05_RemoveFunctions.s.sol --sig \"runWithParams(address,address,string)\" \\"
            );
            console2.log("  $METAVAULT_ADDRESS $MODULE_ADDRESS \"moduleType\" \\");
            console2.log("  --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY --broadcast");

            console2.log("\n[INFO] Available module types:");
            for (uint256 i = 0; i < knownModuleTypes.length; i++) {
                console2.log("  - ", knownModuleTypes[i]);
            }
            return;
        }

        executeRemoveFunctions();
    }

    /**
     * @notice Run function with direct parameters
     * @param _metavaultAddress Address of the MetaVault contract
     * @param _moduleAddress Address of the module whose functions to remove
     * @param _moduleType Type of module (engine, assetsManager, etc.)
     */
    function runWithParams(address _metavaultAddress, address _moduleAddress, string memory _moduleType) public {
        console2.log("\n=======================================================");
        console2.log("        REMOVING FUNCTIONS FROM METAVAULT");
        console2.log("=======================================================\n");

        console2.log("[INFO] Using directly provided parameters");

        // Still need private key from environment
        try vm.envUint("ADMIN_PRIVATE_KEY") returns (uint256 key) {
            adminPrivateKey = key;
            console2.log("[SUCCESS] Loaded ADMIN_PRIVATE_KEY from environment variables");
        } catch {
            console2.log("[ERROR] Failed to load ADMIN_PRIVATE_KEY from environment");
            console2.log("ADMIN_PRIVATE_KEY environment variable is required even when using direct parameters");
            return;
        }

        // Validate parameters
        if (_metavaultAddress == address(0)) {
            console2.log("[ERROR] MetaVault address cannot be zero address");
            return;
        }
        if (_moduleAddress == address(0)) {
            console2.log("[ERROR] Module address cannot be zero address");
            return;
        }

        // Check if module type is recognized
        bool validModuleType = false;
        for (uint256 i = 0; i < knownModuleTypes.length; i++) {
            if (_stringsEqual(_moduleType, knownModuleTypes[i])) {
                validModuleType = true;
                break;
            }
        }

        if (!validModuleType) {
            console2.log("[WARNING] Unrecognized module type:", _moduleType);
            console2.log("[INFO] Available module types:");
            for (uint256 i = 0; i < knownModuleTypes.length; i++) {
                console2.log("  - ", knownModuleTypes[i]);
            }
            console2.log(
                "[INFO] Continuing with custom module type. Make sure the module implements a 'selectors()' function."
            );
        }

        metavault = IMetaVault(_metavaultAddress);
        moduleAddress = _moduleAddress;
        moduleType = _moduleType;
        parametersLoaded = true;

        executeRemoveFunctions();
    }

    /**
     * @notice Loads parameters from environment variables
     * @dev This is exposed as an external function to allow try/catch in the main run function
     */
    function loadFromEnv() external {
        adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        if (adminPrivateKey == 0) revert("ADMIN_PRIVATE_KEY not set or invalid");

        address mvAddress = vm.envAddress("METAVAULT_ADDRESS");
        if (mvAddress == address(0)) revert("METAVAULT_ADDRESS not set or invalid");
        metavault = IMetaVault(mvAddress);

        address modAddress = vm.envAddress("MODULE_ADDRESS");
        if (modAddress == address(0)) revert("MODULE_ADDRESS not set or invalid");
        moduleAddress = modAddress;

        // Module type is optional in env vars - if not provided, we'll try to detect it
        try vm.envString("MODULE_TYPE") returns (string memory modType) {
            if (bytes(modType).length > 0) {
                moduleType = modType;
                console2.log("[INFO] Using MODULE_TYPE from environment:", moduleType);
            } else {
                moduleType = "custom";
                console2.log("[INFO] Empty MODULE_TYPE, will try to detect from address");
            }
        } catch {
            moduleType = "custom";
            console2.log("[INFO] MODULE_TYPE not set, will try to detect from address");
        }

        parametersLoaded = true;
    }

    /**
     * @notice Executes the function removal
     */
    function executeRemoveFunctions() private {
        if (!parametersLoaded) {
            console2.log("[ERROR] Cannot execute: parameters not loaded");
            return;
        }

        console2.log("\n[PARAMETERS] Configuration Parameters:");
        console2.log(" - MetaVault Address:", address(metavault));
        console2.log(" - Module Address:", moduleAddress);
        console2.log(" - Module Type:", moduleType);
        console2.log(" - Admin Account:", vm.addr(adminPrivateKey));

        console2.log("\n[EXECUTING] Removing functions from MetaVault...");

        bytes4[] memory selectors = getModuleSelectors();

        if (selectors.length == 0) {
            console2.log("[ERROR] No selectors found for module");
            return;
        }

        console2.log("[INFO] Found", selectors.length, "function selectors to remove");

        vm.startBroadcast(adminPrivateKey);

        try metavault.removeFunctions(selectors) {
            console2.log("[SUCCESS] Successfully removed", selectors.length, "functions from MetaVault");
        } catch (bytes memory reason) {
            console2.log("[ERROR] Failed to remove functions");
            console2.logBytes(reason);
        }

        vm.stopBroadcast();

        console2.log("\n=======================================================");
        console2.log("               OPERATION COMPLETED");
        console2.log("=======================================================");
    }

    /**
     * @notice Get function selectors based on module type
     * @return Function selectors for the specified module
     */
    function getModuleSelectors() private returns (bytes4[] memory) {
        if (_stringsEqual(moduleType, "engine")) {
            return ERC7540Engine(moduleAddress).selectors();
        } else if (_stringsEqual(moduleType, "engineReader")) {
            return ERC7540EngineReader(moduleAddress).selectors();
        } else if (_stringsEqual(moduleType, "engineSignatures")) {
            return ERC7540EngineSignatures(moduleAddress).selectors();
        } else if (_stringsEqual(moduleType, "assetsManager")) {
            return AssetsManager(moduleAddress).selectors();
        } else if (_stringsEqual(moduleType, "metaVaultReader")) {
            return MetaVaultReader(moduleAddress).selectors();
        } else if (_stringsEqual(moduleType, "emergencyAssetsManager")) {
            return EmergencyAssetsManager(moduleAddress).selectors();
        } else {
            // Try generic call for custom modules
            console2.log("[INFO] Using generic selector call for custom module type");

            (bool success, bytes memory data) = moduleAddress.call(abi.encodeWithSignature("selectors()"));

            if (success && data.length > 0) {
                return abi.decode(data, (bytes4[]));
            } else {
                console2.log("[ERROR] Failed to get selectors from module. Ensure it has a selectors() function.");
                return new bytes4[](0);
            }
        }
    }

    /**
     * @notice Compare two strings for equality
     * @param a First string
     * @param b Second string
     * @return True if strings are equal, false otherwise
     */
    function _stringsEqual(string memory a, string memory b) private pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
