//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SuperformGateway } from "crosschain/SuperformGateway/Lib.sol";
import { Script, console2 } from "forge-std/Script.sol";

import { ISuperformGateway } from "interfaces/Lib.sol";

/**
 * @title SetRecoveryAddress
 * @notice Script for setting the recovery address on the SuperformGateway
 * @dev Can be run using CLI parameters or environment variables
 *
 * Environment Variables:
 * - DEPLOYER_PRIVATE_KEY: Private key for deployment
 * - SUPERFORM_GATEWAY_ADDRESS: Address of the SuperformGateway contract
 * - SUPER_POSITIONS_RECEIVER_ADDRESS: Address of the SuperPositionsReceiver to set as recovery address
 *
 * CLI Usage:
 * forge script script/base/04_SetRecoveryAddress.s.sol --sig "runWithParams(address,address)" \
 *   $SUPERFORM_GATEWAY_ADDRESS $SUPER_POSITIONS_RECEIVER_ADDRESS \
 *   --rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --broadcast
 */
contract SetRecoveryAddress is Script {
    ISuperformGateway public gateway;

    uint256 private deployerPrivateKey;
    address private gatewayAddress;
    address private superPositionsReceiverAddress;
    bool private parametersLoaded = false;

    /**
     * @notice Default run function using environment variables
     */
    function run() public {
        console2.log("\n=======================================================");
        console2.log("     SETTING RECOVERY ADDRESS ON GATEWAY");
        console2.log("=======================================================\n");

        console2.log("[INFO] Loading parameters from environment variables...");

        try this.loadFromEnv() {
            console2.log("[SUCCESS] Successfully loaded all parameters from environment variables");
        } catch Error(string memory reason) {
            console2.log("[ERROR] Failed to load parameters:", reason);
            console2.log("\n[HINT] You can also run with direct parameters using:");
            console2.log(
                "forge script script/base/04_SetRecoveryAddress.s.sol --sig \"runWithParams(address,address)\" \\"
            );
            console2.log("  $SUPERFORM_GATEWAY_ADDRESS $SUPER_POSITIONS_RECEIVER_ADDRESS \\");
            console2.log("  --rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --broadcast");
            return;
        }

        executeSetRecoveryAddress();
    }

    /**
     * @notice Run function with direct parameters
     * @param _gatewayAddress Address of the SuperformGateway contract
     * @param _receiverAddress Address of the SuperPositionsReceiver
     */
    function runWithParams(address _gatewayAddress, address _receiverAddress) public {
        console2.log("\n=======================================================");
        console2.log("     SETTING RECOVERY ADDRESS ON GATEWAY");
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
        if (_gatewayAddress == address(0)) {
            console2.log("[ERROR] Gateway address cannot be zero address");
            return;
        }
        if (_receiverAddress == address(0)) {
            console2.log("[ERROR] Receiver address cannot be zero address");
            return;
        }

        gatewayAddress = _gatewayAddress;
        superPositionsReceiverAddress = _receiverAddress;
        parametersLoaded = true;

        executeSetRecoveryAddress();
    }

    /**
     * @notice Loads parameters from environment variables
     * @dev This is exposed as an external function to allow try/catch in the main run function
     */
    function loadFromEnv() external {
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        if (deployerPrivateKey == 0) revert("DEPLOYER_PRIVATE_KEY not set or invalid");

        address gateway = vm.envAddress("SUPERFORM_GATEWAY_ADDRESS");
        if (gateway == address(0)) revert("SUPERFORM_GATEWAY_ADDRESS not set or invalid");
        gatewayAddress = gateway;

        address receiver = vm.envAddress("SUPER_POSITIONS_RECEIVER_ADDRESS");
        if (receiver == address(0)) revert("SUPER_POSITIONS_RECEIVER_ADDRESS not set or invalid");
        superPositionsReceiverAddress = receiver;

        parametersLoaded = true;
    }

    /**
     * @notice Executes setting the recovery address
     */
    function executeSetRecoveryAddress() private {
        if (!parametersLoaded) {
            console2.log("[ERROR] Cannot execute: parameters not loaded");
            return;
        }

        console2.log("\n[PARAMETERS] Configuration Parameters:");
        console2.log(" - Gateway Address:", gatewayAddress);
        console2.log(" - Recovery Address:", superPositionsReceiverAddress);
        console2.log(" - Deployer Account:", vm.addr(deployerPrivateKey));

        console2.log("\n[EXECUTING] Setting recovery address on gateway...");

        vm.startBroadcast(deployerPrivateKey);

        // Check if we can load the gateway interface
        try ISuperformGateway(gatewayAddress).ADMIN_ROLE() returns (uint256) {
            // Gateway interface is valid, proceed
            gateway = ISuperformGateway(gatewayAddress);

            // Check current recovery address
            address currentRecovery;
            try gateway.recoveryAddress() returns (address addr) {
                currentRecovery = addr;
                console2.log("[INFO] Current recovery address:", currentRecovery);
            } catch {
                console2.log("[WARNING] Could not query current recovery address");
            }

            // Set the new recovery address
            try gateway.setRecoveryAddress(superPositionsReceiverAddress) {
                console2.log("[SUCCESS] Successfully set recovery address to:", superPositionsReceiverAddress);

                // Verify the change
                try gateway.recoveryAddress() returns (address newAddr) {
                    if (newAddr == superPositionsReceiverAddress) {
                        console2.log("[VERIFIED] Recovery address change confirmed");
                    } else {
                        console2.log("[WARNING] Recovery address does not match expected value:", newAddr);
                    }
                } catch {
                    console2.log("[WARNING] Could not verify recovery address after update");
                }
            } catch (bytes memory reason) {
                console2.log("[ERROR] Failed to set recovery address");
                console2.logBytes(reason);
            }
        } catch {
            console2.log("[ERROR] Failed to interact with gateway at address:", gatewayAddress);
            console2.log("Ensure this is a valid SuperformGateway contract");
        }

        vm.stopBroadcast();

        console2.log("\n=======================================================");
        console2.log("               OPERATION COMPLETED");
        console2.log("=======================================================");
    }
}
