//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    DivestSuperform, InvestSuperform, LiquidateSuperform, SuperformGateway
} from "crosschain/SuperformGateway/Lib.sol";
import { Script, console2 } from "forge-std/Script.sol";
import { ISuperformGateway } from "interfaces/Lib.sol";

/**
 * @title RemoveGatewayFunctionsScript
 * @notice Script for removing function selectors from SuperformGateway modules
 * @dev Can use CLI parameters or environment variables to specify which modules to remove
 *
 * Environment Variables:
 * - ADMIN_PRIVATE_KEY: Private key for the admin account
 * - SUPERFORM_GATEWAY_ADDRESS: Address of the SuperformGateway contract
 * - MODULES_TO_REMOVE: Comma-separated list of module types to remove (invest,divest,liquidate)
 * - INVEST_ADDRESS: (Optional) Address of the InvestSuperform module
 * - DIVEST_ADDRESS: (Optional) Address of the DivestSuperform module
 * - LIQUIDATE_ADDRESS: (Optional) Address of the LiquidateSuperform module
 *
 * CLI Usage:
 * forge script script/base/07_RemoveFunctionsGateway.s.sol --sig
 * "runWithParams(address,string,address,address,address)" \
 *   $SUPERFORM_GATEWAY_ADDRESS "invest,divest,liquidate" $INVEST_ADDRESS $DIVEST_ADDRESS $LIQUIDATE_ADDRESS \
 *   --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY --broadcast
 */
contract RemoveGatewayFunctionsScript is Script {
    // Contract instances
    ISuperformGateway public gateway;
    address private investAddress;
    address private divestAddress;
    address private liquidateAddress;

    // Configuration
    uint256 private adminPrivateKey;
    string private modulesToRemove;
    bool private parametersLoaded = false;

    // Tracking which modules to remove
    bool private removeInvest;
    bool private removeDivest;
    bool private removeLiquidate;

    /**
     * @notice Default run function using environment variables
     */
    function run() public {
        console2.log("\n=======================================================");
        console2.log("    REMOVING FUNCTIONS FROM SUPERFORM GATEWAY");
        console2.log("=======================================================\n");

        console2.log("[INFO] Loading parameters from environment variables...");

        try this.loadFromEnv() {
            console2.log("[SUCCESS] Successfully loaded all parameters from environment variables");
        } catch Error(string memory reason) {
            console2.log("[ERROR] Failed to load parameters:", reason);
            console2.log("\n[HINT] You can also run with direct parameters using:");
            console2.log(
                "forge script script/base/07_RemoveFunctionsGateway.s.sol --sig \"runWithParams(address,string,address,address,address)\" \\"
            );
            console2.log(
                "  $SUPERFORM_GATEWAY_ADDRESS \"invest,divest,liquidate\" $INVEST_ADDRESS $DIVEST_ADDRESS $LIQUIDATE_ADDRESS \\"
            );
            console2.log("  --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY --broadcast");
            return;
        }

        executeRemoveFunctions();
    }

    /**
     * @notice Run function with direct parameters
     * @param _gatewayAddress Address of the SuperformGateway contract
     * @param _modulesToRemove Comma-separated list of modules to remove (invest,divest,liquidate)
     * @param _investAddress Address of the InvestSuperform module (0x0 to skip)
     * @param _divestAddress Address of the DivestSuperform module (0x0 to skip)
     * @param _liquidateAddress Address of the LiquidateSuperform module (0x0 to skip)
     */
    function runWithParams(
        address _gatewayAddress,
        string memory _modulesToRemove,
        address _investAddress,
        address _divestAddress,
        address _liquidateAddress
    )
        public
    {
        console2.log("\n=======================================================");
        console2.log("    REMOVING FUNCTIONS FROM SUPERFORM GATEWAY");
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
        if (_gatewayAddress == address(0)) {
            console2.log("[ERROR] Gateway address cannot be zero address");
            return;
        }

        gateway = ISuperformGateway(payable(_gatewayAddress));
        modulesToRemove = _modulesToRemove;
        investAddress = _investAddress;
        divestAddress = _divestAddress;
        liquidateAddress = _liquidateAddress;

        // Parse modules to remove
        _parseModulesToRemove();

        // Check addresses for selected modules
        _validateModuleAddresses();

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

        address gatewayAddr = vm.envAddress("SUPERFORM_GATEWAY_ADDRESS");
        if (gatewayAddr == address(0)) revert("SUPERFORM_GATEWAY_ADDRESS not set or invalid");
        gateway = ISuperformGateway(payable(gatewayAddr));

        modulesToRemove = vm.envString("MODULES_TO_REMOVE");
        if (bytes(modulesToRemove).length == 0) revert("MODULES_TO_REMOVE not set or invalid");

        // Parse modules to remove
        _parseModulesToRemove();

        // Load module addresses if needed
        if (removeInvest) {
            investAddress = vm.envAddress("INVEST_ADDRESS");
            if (investAddress == address(0)) revert("INVEST_ADDRESS not set or invalid");
        }

        if (removeDivest) {
            divestAddress = vm.envAddress("DIVEST_ADDRESS");
            if (divestAddress == address(0)) revert("DIVEST_ADDRESS not set or invalid");
        }

        if (removeLiquidate) {
            liquidateAddress = vm.envAddress("LIQUIDATE_ADDRESS");
            if (liquidateAddress == address(0)) revert("LIQUIDATE_ADDRESS not set or invalid");
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
        console2.log(" - Gateway Address:", address(gateway));
        console2.log(" - Modules to Remove:", modulesToRemove);
        if (removeInvest) console2.log(" - Invest Module Address:", investAddress);
        if (removeDivest) console2.log(" - Divest Module Address:", divestAddress);
        if (removeLiquidate) console2.log(" - Liquidate Module Address:", liquidateAddress);
        console2.log(" - Admin Account:", vm.addr(adminPrivateKey));

        console2.log("\n[EXECUTING] Removing functions from SuperformGateway...");

        vm.startBroadcast(adminPrivateKey);

        uint256 totalSelectorsRemoved = 0;

        // Remove InvestSuperform functions
        if (removeInvest) {
            try InvestSuperform(investAddress).selectors() returns (bytes4[] memory selectors) {
                console2.log("[INFO] Removing", selectors.length, "functions from InvestSuperform module");

                try gateway.removeFunctions(selectors) {
                    console2.log("[SUCCESS] Successfully removed InvestSuperform functions");
                    totalSelectorsRemoved += selectors.length;
                } catch (bytes memory reason) {
                    console2.log("[ERROR] Failed to remove InvestSuperform functions");
                    console2.logBytes(reason);
                }
            } catch {
                console2.log("[ERROR] Failed to get selectors from InvestSuperform at", investAddress);
            }
        }

        // Remove DivestSuperform functions
        if (removeDivest) {
            try DivestSuperform(divestAddress).selectors() returns (bytes4[] memory selectors) {
                console2.log("[INFO] Removing", selectors.length, "functions from DivestSuperform module");

                try gateway.removeFunctions(selectors) {
                    console2.log("[SUCCESS] Successfully removed DivestSuperform functions");
                    totalSelectorsRemoved += selectors.length;
                } catch (bytes memory reason) {
                    console2.log("[ERROR] Failed to remove DivestSuperform functions");
                    console2.logBytes(reason);
                }
            } catch {
                console2.log("[ERROR] Failed to get selectors from DivestSuperform at", divestAddress);
            }
        }

        // Remove LiquidateSuperform functions
        if (removeLiquidate) {
            try LiquidateSuperform(liquidateAddress).selectors() returns (bytes4[] memory selectors) {
                console2.log("[INFO] Removing", selectors.length, "functions from LiquidateSuperform module");

                try gateway.removeFunctions(selectors) {
                    console2.log("[SUCCESS] Successfully removed LiquidateSuperform functions");
                    totalSelectorsRemoved += selectors.length;
                } catch (bytes memory reason) {
                    console2.log("[ERROR] Failed to remove LiquidateSuperform functions");
                    console2.logBytes(reason);
                }
            } catch {
                console2.log("[ERROR] Failed to get selectors from LiquidateSuperform at", liquidateAddress);
            }
        }

        vm.stopBroadcast();

        console2.log("\n[SUMMARY] Function Removal:");
        console2.log(" - Total selectors removed:", totalSelectorsRemoved);

        console2.log("\n=======================================================");
        console2.log("               OPERATION COMPLETED");
        console2.log("=======================================================");
    }

    /**
     * @notice Parses the modulesToRemove string and sets the appropriate flags
     */
    function _parseModulesToRemove() private {
        string memory modules = modulesToRemove;
        removeInvest = _containsModule(modules, "invest");
        removeDivest = _containsModule(modules, "divest");
        removeLiquidate = _containsModule(modules, "liquidate");

        if (!removeInvest && !removeDivest && !removeLiquidate) {
            console2.log("[WARNING] No valid modules specified to remove. Valid modules are: invest, divest, liquidate");
            console2.log("[WARNING] Please use comma-separated values, e.g., 'invest,divest,liquidate'");
        }
    }

    /**
     * @notice Validates that addresses are provided for selected modules
     */
    function _validateModuleAddresses() private {
        if (removeInvest && investAddress == address(0)) {
            console2.log("[ERROR] Invest module selected for removal but no address provided");
            parametersLoaded = false;
        }

        if (removeDivest && divestAddress == address(0)) {
            console2.log("[ERROR] Divest module selected for removal but no address provided");
            parametersLoaded = false;
        }

        if (removeLiquidate && liquidateAddress == address(0)) {
            console2.log("[ERROR] Liquidate module selected for removal but no address provided");
            parametersLoaded = false;
        }
    }

    /**
     * @notice Checks if a module name is contained in a comma-separated list
     * @param list The comma-separated list of module names
     * @param module The module name to check for
     * @return True if the module is in the list, false otherwise
     */
    function _containsModule(string memory list, string memory module) private pure returns (bool) {
        bytes memory listBytes = bytes(list);
        bytes memory moduleBytes = bytes(module);

        // Check each possible starting position in the list
        for (uint256 i = 0; i < listBytes.length; i++) {
            bool _match = true;

            // If there's not enough space left for the module, skip
            if (i + moduleBytes.length > listBytes.length) continue;

            // Check if module _matches at this position
            for (uint256 j = 0; j < moduleBytes.length; j++) {
                if (listBytes[i + j] != moduleBytes[j]) {
                    _match = false;
                    break;
                }
            }

            // If we found a _match, check it's a complete word (surrounded by commas or at string boundaries)
            if (_match) {
                bool startBoundary = (i == 0 || listBytes[i - 1] == "," || listBytes[i - 1] == " ");
                bool endBoundary = (
                    i + moduleBytes.length == listBytes.length || listBytes[i + moduleBytes.length] == ","
                        || listBytes[i + moduleBytes.length] == " "
                );

                if (startBoundary && endBoundary) return true;
            }
        }

        return false;
    }
}
