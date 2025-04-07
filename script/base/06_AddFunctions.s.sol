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
 * @title AddFunctionsScript
 * @notice Script for deploying and adding module functions to MetaVault
 * @dev Can use CLI parameters or environment variables to specify which module to deploy and add
 *
 * Environment Variables:
 * - ADMIN_PRIVATE_KEY: Private key for the admin account
 * - METAVAULT_ADDRESS: Address of the MetaVault contract
 * - MODULE_TYPE: Type of module to deploy and add (engine, assetsManager, etc.)
 * - FORCE_OVERRIDE: (Optional) Whether to force override existing functions (true/false)
 *
 * CLI Usage:
 * forge script script/base/06_AddFunctions.s.sol --sig "runWithParams(address,string,bool)" \
 *   $METAVAULT_ADDRESS "engine" false \
 *   --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY --broadcast
 */
contract AddFunctionsScript is Script {
    // Contract instances
    IMetaVault public metavault;
    address public deployedModule;

    // Configuration
    uint256 private adminPrivateKey;
    string private moduleType;
    bool private forceOverride;
    bool private parametersLoaded = false;

    // Known module types mapping
    struct ModuleInfo {
        string name;
        string description;
    }

    ModuleInfo[] private knownModules;

    constructor() {
        // Initialize known module types
        knownModules.push(ModuleInfo("engine", "ERC7540Engine - Core redemption processing engine"));
        knownModules.push(ModuleInfo("engineReader", "ERC7540EngineReader - Read-only functions for the engine"));
        knownModules.push(
            ModuleInfo("engineSignatures", "ERC7540EngineSignatures - Signature verification for redemptions")
        );
        knownModules.push(ModuleInfo("assetsManager", "AssetsManager - Management of vault assets"));
        knownModules.push(ModuleInfo("metaVaultReader", "MetaVaultReader - Read-only functions for vault state"));
        knownModules.push(
            ModuleInfo("emergencyAssetsManager", "EmergencyAssetsManager - Emergency recovery operations")
        );
    }

    /**
     * @notice Default run function using environment variables
     */
    function run() public {
        console2.log("\n=======================================================");
        console2.log("        DEPLOYING AND ADDING MODULE FUNCTIONS");
        console2.log("=======================================================\n");

        console2.log("[INFO] Loading parameters from environment variables...");

        try this.loadFromEnv() {
            console2.log("[SUCCESS] Successfully loaded all parameters from environment variables");
        } catch Error(string memory reason) {
            console2.log("[ERROR] Failed to load parameters:", reason);

            // Show available module types
            _displayAvailableModules();

            console2.log("\n[HINT] You can also run with direct parameters using:");
            console2.log(
                "forge script script/base/06_AddFunctions.s.sol --sig \"runWithParams(address,string,bool)\" \\"
            );
            console2.log("  $METAVAULT_ADDRESS \"moduleType\" false \\");
            console2.log("  --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY --broadcast");
            return;
        }

        executeAddFunctions();
    }

    /**
     * @notice Run function with direct parameters
     * @param _metavaultAddress Address of the MetaVault contract
     * @param _moduleType Type of module to deploy (engine, assetsManager, etc.)
     * @param _forceOverride Whether to force override existing functions
     */
    function runWithParams(address _metavaultAddress, string memory _moduleType, bool _forceOverride) public {
        console2.log("\n=======================================================");
        console2.log("        DEPLOYING AND ADDING MODULE FUNCTIONS");
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

        // Check if module type is recognized
        bool validModuleType = false;
        for (uint256 i = 0; i < knownModules.length; i++) {
            if (_stringsEqual(_moduleType, knownModules[i].name)) {
                validModuleType = true;
                break;
            }
        }

        if (!validModuleType) {
            console2.log("[ERROR] Unrecognized module type:", _moduleType);
            _displayAvailableModules();
            return;
        }

        metavault = IMetaVault(_metavaultAddress);
        moduleType = _moduleType;
        forceOverride = _forceOverride;
        parametersLoaded = true;

        executeAddFunctions();
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

        string memory modType = vm.envString("MODULE_TYPE");
        if (bytes(modType).length == 0) revert("MODULE_TYPE not set or invalid");
        moduleType = modType;

        // Check if module type is valid
        bool validModuleType = false;
        for (uint256 i = 0; i < knownModules.length; i++) {
            if (_stringsEqual(moduleType, knownModules[i].name)) {
                validModuleType = true;
                break;
            }
        }

        if (!validModuleType) {
            revert(string(abi.encodePacked("Invalid MODULE_TYPE: ", moduleType)));
        }

        // Force override is optional, defaults to false
        try vm.envBool("FORCE_OVERRIDE") returns (bool _override) {
            forceOverride = _override;
            console2.log("[INFO] Using FORCE_OVERRIDE from environment:", forceOverride ? "true" : "false");
        } catch {
            forceOverride = false;
            console2.log("[INFO] FORCE_OVERRIDE not set, defaulting to false");
        }

        parametersLoaded = true;
    }

    /**
     * @notice Executes the module deployment and function addition
     */
    function executeAddFunctions() private {
        if (!parametersLoaded) {
            console2.log("[ERROR] Cannot execute: parameters not loaded");
            return;
        }

        console2.log("\n[PARAMETERS] Configuration Parameters:");
        console2.log(" - MetaVault Address:", address(metavault));
        console2.log(" - Module Type:", moduleType);
        console2.log(" - Force Override:", forceOverride ? "Yes" : "No");
        console2.log(" - Admin Account:", vm.addr(adminPrivateKey));

        console2.log("\n[EXECUTING] Deploying module and adding functions...");

        vm.startBroadcast(adminPrivateKey);

        // Deploy the module based on type
        deployedModule = deployModule();

        if (deployedModule == address(0)) {
            console2.log("[ERROR] Module deployment failed");
            vm.stopBroadcast();
            return;
        }

        console2.log("[SUCCESS] Module deployed at:", deployedModule);

        // Get selectors and add functions
        bytes4[] memory selectors = getModuleSelectors();

        if (selectors.length == 0) {
            console2.log("[ERROR] No selectors found for module");
            vm.stopBroadcast();
            return;
        }

        console2.log("[INFO] Adding", selectors.length, "function selectors to MetaVault");

        try metavault.addFunctions(selectors, deployedModule, forceOverride) {
            console2.log("[SUCCESS] Successfully added", selectors.length, "functions to MetaVault");
        } catch (bytes memory reason) {
            console2.log("[ERROR] Failed to add functions");
            console2.logBytes(reason);
        }

        vm.stopBroadcast();

        console2.log("\n[SUMMARY] Module Deployment Details:");
        console2.log(" - Module Type:", moduleType);
        console2.log(" - Module Address:", deployedModule);
        console2.log(" - Functions Added:", selectors.length);

        console2.log("\n=======================================================");
        console2.log("               OPERATION COMPLETED");
        console2.log("=======================================================");
        console2.log("To add this module to .env for later scripts, use:");
        console2.log(string(abi.encodePacked(moduleType, "_ADDRESS=", _addressToString(deployedModule))));
    }

    /**
     * @notice Deploy a module based on its type
     * @return Address of the deployed module
     */
    function deployModule() private returns (address) {
        if (_stringsEqual(moduleType, "engine")) {
            return address(new ERC7540Engine());
        } else if (_stringsEqual(moduleType, "engineReader")) {
            return address(new ERC7540EngineReader());
        } else if (_stringsEqual(moduleType, "engineSignatures")) {
            return address(new ERC7540EngineSignatures());
        } else if (_stringsEqual(moduleType, "assetsManager")) {
            return address(new AssetsManager());
        } else if (_stringsEqual(moduleType, "metaVaultReader")) {
            return address(new MetaVaultReader());
        } else if (_stringsEqual(moduleType, "emergencyAssetsManager")) {
            return address(new EmergencyAssetsManager());
        } else {
            console2.log("[ERROR] Unsupported module type for deployment:", moduleType);
            return address(0);
        }
    }

    /**
     * @notice Get function selectors for the deployed module
     * @return Array of function selectors
     */
    function getModuleSelectors() private returns (bytes4[] memory) {
        if (_stringsEqual(moduleType, "engine")) {
            return ERC7540Engine(deployedModule).selectors();
        } else if (_stringsEqual(moduleType, "engineReader")) {
            return ERC7540EngineReader(deployedModule).selectors();
        } else if (_stringsEqual(moduleType, "engineSignatures")) {
            return ERC7540EngineSignatures(deployedModule).selectors();
        } else if (_stringsEqual(moduleType, "assetsManager")) {
            return AssetsManager(deployedModule).selectors();
        } else if (_stringsEqual(moduleType, "metaVaultReader")) {
            return MetaVaultReader(deployedModule).selectors();
        } else if (_stringsEqual(moduleType, "emergencyAssetsManager")) {
            return EmergencyAssetsManager(deployedModule).selectors();
        } else {
            return new bytes4[](0);
        }
    }

    /**
     * @notice Displays available module types
     */
    function _displayAvailableModules() private view {
        console2.log("\n[INFO] Available module types:");
        for (uint256 i = 0; i < knownModules.length; i++) {
            console2.log(string(abi.encodePacked("  - ", knownModules[i].name, ": ", knownModules[i].description)));
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

    /**
     * @notice Convert address to string
     * @param _addr Address to convert
     * @return String representation of the address
     */
    function _addressToString(address _addr) private pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";

        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }

        return string(str);
    }
}
