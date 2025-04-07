//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    DivestSuperform, InvestSuperform, LiquidateSuperform, SuperformGateway
} from "crosschain/SuperformGateway/Lib.sol";
import { Script, console2 } from "forge-std/Script.sol";
import { ISuperformGateway } from "interfaces/Lib.sol";

/**
 * @title AddGatewayFunctionsScript
 * @notice Script for deploying and adding functions to SuperformGateway modules
 * @dev Can use CLI parameters or environment variables to specify which modules to deploy and add
 *
 * Environment Variables:
 * - ADMIN_PRIVATE_KEY: Private key for the admin account
 * - SUPERFORM_GATEWAY_ADDRESS: Address of the SuperformGateway contract
 * - MODULES_TO_ADD: Comma-separated list of module types to add (invest,divest,liquidate)
 * - FORCE_OVERRIDE: (Optional) Whether to force override existing functions (true/false)
 *
 * CLI Usage:
 * forge script script/base/08_AddFunctionsGateway.s.sol --sig "runWithParams(address,string,bool)" \
 *   $SUPERFORM_GATEWAY_ADDRESS "invest,divest,liquidate" false \
 *   --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY --broadcast
 */
contract AddGatewayFunctionsScript is Script {
    // Contract instances
    ISuperformGateway public gateway;
    address public investAddress;
    address public divestAddress;
    address public liquidateAddress;

    // Configuration
    uint256 private adminPrivateKey;
    string private modulesToAdd;
    bool private forceOverride;
    bool private parametersLoaded = false;

    // Tracking which modules to add
    bool private addInvest;
    bool private addDivest;
    bool private addLiquidate;

    /**
     * @notice Default run function using environment variables
     */
    function run() public {
        console2.log("\n=======================================================");
        console2.log("    DEPLOYING AND ADDING FUNCTIONS TO GATEWAY");
        console2.log("=======================================================\n");

        console2.log("[INFO] Loading parameters from environment variables...");

        try this.loadFromEnv() {
            console2.log("[SUCCESS] Successfully loaded all parameters from environment variables");
        } catch Error(string memory reason) {
            console2.log("[ERROR] Failed to load parameters:", reason);
            console2.log("\n[HINT] You can also run with direct parameters using:");
            console2.log(
                "forge script script/base/08_AddFunctionsGateway.s.sol --sig \"runWithParams(address,string,bool)\" \\"
            );
            console2.log("  $SUPERFORM_GATEWAY_ADDRESS \"invest,divest,liquidate\" false \\");
            console2.log("  --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY --broadcast");
            return;
        }

        executeAddFunctions();
    }

    /**
     * @notice Run function with direct parameters
     * @param _gatewayAddress Address of the SuperformGateway contract
     * @param _modulesToAdd Comma-separated list of modules to add (invest,divest,liquidate)
     * @param _forceOverride Whether to force override existing functions
     */
    function runWithParams(address _gatewayAddress, string memory _modulesToAdd, bool _forceOverride) public {
        console2.log("\n=======================================================");
        console2.log("    DEPLOYING AND ADDING FUNCTIONS TO GATEWAY");
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
        modulesToAdd = _modulesToAdd;
        forceOverride = _forceOverride;

        // Parse modules to add
        _parseModulesToAdd();

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

        address gatewayAddr = vm.envAddress("SUPERFORM_GATEWAY_ADDRESS");
        if (gatewayAddr == address(0)) revert("SUPERFORM_GATEWAY_ADDRESS not set or invalid");
        gateway = ISuperformGateway(payable(gatewayAddr));

        modulesToAdd = vm.envString("MODULES_TO_ADD");
        if (bytes(modulesToAdd).length == 0) {
            // Default to all modules if not specified
            modulesToAdd = "invest,divest,liquidate";
            console2.log("[INFO] MODULES_TO_ADD not set, defaulting to 'invest,divest,liquidate'");
        }

        // Parse modules to add
        _parseModulesToAdd();

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
        console2.log(" - Gateway Address:", address(gateway));
        console2.log(" - Modules to Add:", modulesToAdd);
        console2.log(" - Force Override:", forceOverride ? "Yes" : "No");
        console2.log(" - Admin Account:", vm.addr(adminPrivateKey));

        console2.log("\n[EXECUTING] Deploying modules and adding functions...");

        vm.startBroadcast(adminPrivateKey);

        // Deploy and add invest module
        if (addInvest) {
            try new InvestSuperform() returns (InvestSuperform invest) {
                investAddress = address(invest);
                console2.log("[SUCCESS] InvestSuperform deployed at:", investAddress);

                try invest.selectors() returns (bytes4[] memory selectors) {
                    console2.log("[INFO] Adding", selectors.length, "function selectors from InvestSuperform");

                    try gateway.addFunctions(selectors, investAddress, forceOverride) {
                        console2.log("[SUCCESS] Successfully added InvestSuperform functions");
                    } catch (bytes memory reason) {
                        console2.log("[ERROR] Failed to add InvestSuperform functions");
                        console2.logBytes(reason);
                    }
                } catch {
                    console2.log("[ERROR] Failed to get selectors from InvestSuperform");
                }
            } catch {
                console2.log("[ERROR] Failed to deploy InvestSuperform");
            }
        }

        // Deploy and add divest module
        if (addDivest) {
            try new DivestSuperform() returns (DivestSuperform divest) {
                divestAddress = address(divest);
                console2.log("[SUCCESS] DivestSuperform deployed at:", divestAddress);

                try divest.selectors() returns (bytes4[] memory selectors) {
                    console2.log("[INFO] Adding", selectors.length, "function selectors from DivestSuperform");

                    try gateway.addFunctions(selectors, divestAddress, forceOverride) {
                        console2.log("[SUCCESS] Successfully added DivestSuperform functions");
                    } catch (bytes memory reason) {
                        console2.log("[ERROR] Failed to add DivestSuperform functions");
                        console2.logBytes(reason);
                    }
                } catch {
                    console2.log("[ERROR] Failed to get selectors from DivestSuperform");
                }
            } catch {
                console2.log("[ERROR] Failed to deploy DivestSuperform");
            }
        }

        // Deploy and add liquidate module
        if (addLiquidate) {
            try new LiquidateSuperform() returns (LiquidateSuperform liquidate) {
                liquidateAddress = address(liquidate);
                console2.log("[SUCCESS] LiquidateSuperform deployed at:", liquidateAddress);

                try liquidate.selectors() returns (bytes4[] memory selectors) {
                    console2.log("[INFO] Adding", selectors.length, "function selectors from LiquidateSuperform");

                    try gateway.addFunctions(selectors, liquidateAddress, forceOverride) {
                        console2.log("[SUCCESS] Successfully added LiquidateSuperform functions");
                    } catch (bytes memory reason) {
                        console2.log("[ERROR] Failed to add LiquidateSuperform functions");
                        console2.logBytes(reason);
                    }
                } catch {
                    console2.log("[ERROR] Failed to get selectors from LiquidateSuperform");
                }
            } catch {
                console2.log("[ERROR] Failed to deploy LiquidateSuperform");
            }
        }

        vm.stopBroadcast();

        console2.log("\n[SUMMARY] Module Deployment and Addition:");
        if (addInvest) console2.log(" - InvestSuperform Address:", investAddress);
        if (addDivest) console2.log(" - DivestSuperform Address:", divestAddress);
        if (addLiquidate) console2.log(" - LiquidateSuperform Address:", liquidateAddress);

        // Output for .env file
        console2.log("\n[ENV VARIABLES] For your .env file:");
        if (addInvest) console2.log("INVEST_ADDRESS=", _addressToString(investAddress));
        if (addDivest) console2.log("DIVEST_ADDRESS=", _addressToString(divestAddress));
        if (addLiquidate) console2.log("LIQUIDATE_ADDRESS=", _addressToString(liquidateAddress));

        console2.log("\n=======================================================");
        console2.log("               OPERATION COMPLETED");
        console2.log("=======================================================");
    }

    /**
     * @notice Parses the modulesToAdd string and sets the appropriate flags
     */
    function _parseModulesToAdd() private {
        string memory modules = modulesToAdd;
        addInvest = _containsModule(modules, "invest");
        addDivest = _containsModule(modules, "divest");
        addLiquidate = _containsModule(modules, "liquidate");

        if (!addInvest && !addDivest && !addLiquidate) {
            console2.log("[WARNING] No valid modules specified to add. Valid modules are: invest, divest, liquidate");
            console2.log("[WARNING] Please use comma-separated values, e.g., 'invest,divest,liquidate'");
            console2.log("[WARNING] Defaulting to adding all modules");

            addInvest = true;
            addDivest = true;
            addLiquidate = true;
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
