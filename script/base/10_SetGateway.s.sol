//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SuperPositionsReceiver } from "crosschain/SuperPositionsReceiver.sol";
import { Script, console2 } from "forge-std/Script.sol";

/**
 * @title SetGateway
 * @notice Script for setting the gateway address in the SuperPositionsReceiver
 * @dev Can be run using CLI parameters or environment variables
 *
 * Environment Variables:
 * - DEPLOYER_PRIVATE_KEY: Private key for the admin account
 * - SUPERFORM_RECEIVER_ADDRESS: Address of the SuperPositionsReceiver
 * - SUPERFORM_GATEWAY_ADDRESS: Address of the SuperformGateway
 *
 * CLI Usage:
 * forge script script/base/10_SetGateway.s.sol --sig "runWithParams(address,address)" \
 *   $SUPERFORM_RECEIVER_ADDRESS $SUPERFORM_GATEWAY_ADDRESS \
 *   --rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --broadcast
 */
contract SetGateway is Script {
    // Contract instances
    SuperPositionsReceiver public receiver;

    // Configuration
    uint256 private deployerPrivateKey;
    address private receiverAddress;
    address private gatewayAddress;
    bool private parametersLoaded = false;

    /**
     * @notice Default run function using environment variables
     */
    function run() public {
        console2.log("\n=======================================================");
        console2.log("     SETTING GATEWAY IN SUPERPOSITIONS RECEIVER");
        console2.log("=======================================================\n");

        console2.log("[INFO] Loading parameters from environment variables...");

        try this.loadFromEnv() {
            console2.log("[SUCCESS] Successfully loaded all parameters from environment variables");
        } catch Error(string memory reason) {
            console2.log("[ERROR] Failed to load parameters:", reason);
            console2.log("\n[HINT] You can also run with direct parameters using:");
            console2.log("forge script script/base/10_SetGateway.s.sol --sig \"runWithParams(address,address)\" \\");
            console2.log("  $SUPERFORM_RECEIVER_ADDRESS $SUPERFORM_GATEWAY_ADDRESS \\");
            console2.log("  --rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --broadcast");
            return;
        }

        executeSetGateway();
    }

    /**
     * @notice Run function with direct parameters
     * @param _receiverAddress Address of the SuperPositionsReceiver
     * @param _gatewayAddress Address of the SuperformGateway
     */
    function runWithParams(address _receiverAddress, address _gatewayAddress) public {
        console2.log("\n=======================================================");
        console2.log("     SETTING GATEWAY IN SUPERPOSITIONS RECEIVER");
        console2.log("=======================================================\n");

        console2.log("[INFO] Using directly provided parameters");

        // Still need private key from environment
        try vm.envUint("DEPLOYER_PRIVATE_KEY") returns (uint256 key) {
            deployerPrivateKey = key;
            console2.log("[SUCCESS] Loaded DEPLOYER_PRIVATE_KEY from environment variables");
        } catch {
            console2.log("[ERROR] Failed to load DEPLOYER_PRIVATE_KEY from environment");
            console2.log("DEPLOYER_PRIVATE_KEY environment variable is required even when using direct parameters");
            return;
        }

        // Validate parameters
        if (_receiverAddress == address(0)) {
            console2.log("[ERROR] Receiver address cannot be zero address");
            return;
        }

        if (_gatewayAddress == address(0)) {
            console2.log("[ERROR] Gateway address cannot be zero address");
            return;
        }

        receiverAddress = _receiverAddress;
        gatewayAddress = _gatewayAddress;
        parametersLoaded = true;

        executeSetGateway();
    }

    /**
     * @notice Loads parameters from environment variables
     * @dev This is exposed as an external function to allow try/catch in the main run function
     */
    function loadFromEnv() external {
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        if (deployerPrivateKey == 0) revert("DEPLOYER_PRIVATE_KEY not set or invalid");

        address recvAddr = vm.envAddress("SUPERFORM_RECEIVER_ADDRESS");
        if (recvAddr == address(0)) revert("SUPERFORM_RECEIVER_ADDRESS not set or invalid");
        receiverAddress = recvAddr;

        address gwAddr = vm.envAddress("SUPERFORM_GATEWAY_ADDRESS");
        if (gwAddr == address(0)) revert("SUPERFORM_GATEWAY_ADDRESS not set or invalid");
        gatewayAddress = gwAddr;

        parametersLoaded = true;
    }

    /**
     * @notice Executes the setGateway operation
     */
    function executeSetGateway() private {
        if (!parametersLoaded) {
            console2.log("[ERROR] Cannot execute: parameters not loaded");
            return;
        }

        console2.log("\n[PARAMETERS] Configuration Parameters:");
        console2.log(" - SuperPositionsReceiver:", receiverAddress);
        console2.log(" - Gateway Address:", gatewayAddress);
        console2.log(" - Admin Account:", vm.addr(deployerPrivateKey));

        // Initialize SuperPositionsReceiver instance
        receiver = SuperPositionsReceiver(receiverAddress);

        // Check current gateway
        address currentGateway;
        try receiver.gateway() returns (address gw) {
            currentGateway = gw;
            console2.log("[INFO] Current gateway address:", currentGateway);
        } catch {
            console2.log("[WARNING] Could not query current gateway address");
        }

        if (currentGateway == gatewayAddress) {
            console2.log("[WARNING] Gateway address is already set to the target address");
            console2.log("[INFO] Proceeding anyway to ensure proper configuration");
        }

        console2.log("\n[EXECUTING] Setting gateway address...");

        vm.startBroadcast(deployerPrivateKey);

        try receiver.setGateway(gatewayAddress) {
            console2.log("[SUCCESS] Successfully set gateway address to:", gatewayAddress);

            // Verify the change
            try receiver.gateway() returns (address newGw) {
                if (newGw == gatewayAddress) {
                    console2.log("[VERIFIED] Gateway address change confirmed");
                } else {
                    console2.log("[WARNING] Gateway address does not match expected value:", newGw);
                }
            } catch {
                console2.log("[WARNING] Could not verify gateway address after update");
            }
        } catch (bytes memory reason) {
            console2.log("[ERROR] Failed to set gateway address");
            console2.logBytes(reason);
        }

        vm.stopBroadcast();

        console2.log("\n=======================================================");
        console2.log("               OPERATION COMPLETED");
        console2.log("=======================================================");
    }
}
