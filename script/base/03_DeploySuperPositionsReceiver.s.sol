//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { SuperPositionsReceiver } from "../../src/crosschain/SuperPositionsReceiver.sol";
import { SUPERFORM_SUPERPOSITIONS_BASE } from "../../src/helpers/AddressBook.sol";
import "forge-std/Script.sol";

/**
 * @title DeploySuperPositionsReceiver
 * @notice Script for deploying the SuperPositionsReceiver contract with CREATE2
 * @dev Can be run using CLI parameters or environment variables
 *
 * Environment Variables:
 * - ADMIN_PRIVATE_KEY: Private key for deployment
 * - CREATE2_DEPLOYER_ADDRESS: Address of the CREATE2 factory deployer
 * - SUPERFORM_GATEWAY_ADDRESS: Address of the SuperformGateway contract
 * - ADMIN_AND_OWNER_ROLE: Address of the admin/owner role
 * - CHAIN_ID: (Optional) Chain ID for the deployment (default: 8453 for Base)
 *
 * CLI Usage:
 * forge script script/base/03_DeploySuperPositionsReceiver.s.sol --sig "runWithParams(address,address,uint64,address)"
 * \
 *   $CREATE2_DEPLOYER_ADDRESS $SUPERFORM_GATEWAY_ADDRESS $CHAIN_ID $ADMIN_AND_OWNER_ROLE \
 *   --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY --broadcast
 */
contract DeploySuperPositionsReceiver is Script {
    uint256 private adminPrivateKey;
    bool private parametersLoaded = false;

    // Deployment parameters
    address private create2Deployer;
    address private gateway;
    address private superpositions;
    address private owner;
    uint64 private chainId;

    /**
     * @notice Default run function using environment variables
     */
    function run() external {
        console2.log("\n=======================================================");
        console2.log("      DEPLOYING SUPER POSITIONS RECEIVER");
        console2.log("=======================================================\n");

        console2.log("[INFO] Loading parameters from environment variables...");

        try this.loadFromEnv() {
            console2.log("[SUCCESS] Successfully loaded all parameters from environment variables");
        } catch Error(string memory reason) {
            console2.log("[ERROR] Failed to load parameters:", reason);
            console2.log("\n[HINT] You can also run with direct parameters using:");
            console2.log(
                "forge script script/base/03_DeploySuperPositionsReceiver.s.sol --sig \"runWithParams(address,address,uint64,address)\" \\"
            );
            console2.log("  $CREATE2_DEPLOYER_ADDRESS $SUPERFORM_GATEWAY_ADDRESS $CHAIN_ID $ADMIN_AND_OWNER_ROLE \\");
            console2.log("  --rpc-url $RPC_URL --private-key $ADMIN_PRIVATE_KEY --broadcast");
            return;
        }

        executeDeployment();
    }

    /**
     * @notice Run function with direct parameters
     * @param _create2Deployer Address of the CREATE2 factory deployer
     * @param _gateway Address of the SuperformGateway contract
     * @param _chainId Chain ID for the deployment
     * @param _owner Address of the admin/owner role
     */
    function runWithParams(address _create2Deployer, address _gateway, uint64 _chainId, address _owner) external {
        console2.log("\n=======================================================");
        console2.log("      DEPLOYING SUPER POSITIONS RECEIVER");
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
        if (_create2Deployer == address(0)) {
            console2.log("[ERROR] CREATE2_DEPLOYER_ADDRESS cannot be zero address");
            return;
        }
        if (_gateway == address(0)) {
            console2.log("[ERROR] SUPERFORM_GATEWAY_ADDRESS cannot be zero address");
            return;
        }
        if (_owner == address(0)) {
            console2.log("[ERROR] ADMIN_AND_OWNER_ROLE cannot be zero address");
            return;
        }
        if (_chainId == 0) {
            console2.log("[WARNING] CHAIN_ID is zero, defaulting to 8453 (Base)");
            _chainId = 8453;
        }

        create2Deployer = _create2Deployer;
        gateway = _gateway;
        chainId = _chainId;
        owner = _owner;
        superpositions = SUPERFORM_SUPERPOSITIONS_BASE;

        parametersLoaded = true;

        executeDeployment();
    }

    /**
     * @notice Loads parameters from environment variables
     * @dev This is exposed as an external function to allow try/catch in the main run function
     */
    function loadFromEnv() external {
        adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        if (adminPrivateKey == 0) revert("ADMIN_PRIVATE_KEY not set or invalid");

        address createDeployer = vm.envAddress("CREATE2_DEPLOYER_ADDRESS");
        if (createDeployer == address(0)) revert("CREATE2_DEPLOYER_ADDRESS not set or invalid");
        create2Deployer = createDeployer;

        address gatewayAddress = vm.envAddress("SUPERFORM_GATEWAY_ADDRESS");
        if (gatewayAddress == address(0)) revert("SUPERFORM_GATEWAY_ADDRESS not set or invalid");
        gateway = gatewayAddress;

        address ownerAddress = vm.envAddress("ADMIN_AND_OWNER_ROLE");
        if (ownerAddress == address(0)) revert("ADMIN_AND_OWNER_ROLE not set or invalid");
        owner = ownerAddress;

        // Optional: Use environment variable for chain ID if available, otherwise default to Base (8453)
        try vm.envUint("CHAIN_ID") returns (uint256 id) {
            chainId = uint64(id);
            console2.log("[INFO] Using CHAIN_ID from environment:", chainId);
        } catch {
            chainId = 8453; // Default to Base
            console2.log("[INFO] CHAIN_ID not set, defaulting to 8453 (Base)");
        }

        superpositions = SUPERFORM_SUPERPOSITIONS_BASE;

        parametersLoaded = true;
    }

    /**
     * @notice Executes the deployment of SuperPositionsReceiver
     */
    function executeDeployment() private {
        if (!parametersLoaded) {
            console2.log("[ERROR] Cannot execute: parameters not loaded");
            return;
        }

        console2.log("\n[PARAMETERS] Deployment Parameters:");
        console2.log(" - CREATE2 Deployer:", create2Deployer);
        console2.log(" - Gateway Address:", gateway);
        console2.log(" - Chain ID:", chainId);
        console2.log(" - SuperPositions:", superpositions);
        console2.log(" - Owner Address:", owner);
        console2.log(" - Deployer Account:", vm.addr(adminPrivateKey));

        // Compute deterministic address before deployment
        bytes32 salt = keccak256(abi.encode(chainId, gateway, superpositions, owner));
        bytes memory bytecode = abi.encodePacked(
            type(SuperPositionsReceiver).creationCode, abi.encode(chainId, gateway, superpositions, owner)
        );

        address predictedAddress = _getCreate2Address(create2Deployer, salt, bytecode);
        console2.log("\n[INFO] Predicted deployment address:", predictedAddress);

        console2.log("\n[EXECUTING] Deploying SuperPositionsReceiver via CREATE2...");
        vm.startBroadcast(adminPrivateKey);

        (bool success, bytes memory returnData) = create2Deployer.call(abi.encodePacked(salt, bytecode));

        vm.stopBroadcast();

        if (success) {
            console2.log("[SUCCESS] SuperPositionsReceiver deployed successfully");
            console2.log("[ADDRESS] SuperPositionsReceiver:", predictedAddress);

            // Verify if code exists at the predicted address
            uint256 codeSize = address(predictedAddress).code.length;
            if (codeSize > 0) {
                console2.log("[VERIFIED] Contract deployed with code size:", codeSize);
            } else {
                console2.log("[WARNING] No code detected at the predicted address. Deployment might have failed.");
            }
        } else {
            console2.log("[ERROR] SuperPositionsReceiver deployment failed");
            if (returnData.length > 0) {
                // Try to decode revert reason if available
                string memory revertReason = _decodeRevertReason(returnData);
                console2.log("Revert reason:", revertReason);
            }
        }

        console2.log("\n=======================================================");
        console2.log("               OPERATION COMPLETED");
        console2.log("=======================================================");
    }

    /**
     * @notice Predicts the CREATE2 deployment address
     * @param deployer The CREATE2 factory deployer address
     * @param salt The salt used for deployment
     * @param bytecode The contract bytecode
     * @return The predicted contract address
     */
    function _getCreate2Address(address deployer, bytes32 salt, bytes memory bytecode) private pure returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, keccak256(bytecode)));

        // Cast last 20 bytes of hash to address
        return address(uint160(uint256(hash)));
    }

    /**
     * @notice Attempts to decode a revert reason from return data
     * @param data The return data from a failed call
     * @return The decoded revert reason or a generic message
     */
    function _decodeRevertReason(bytes memory data) private pure returns (string memory) {
        if (data.length < 68) return "Unknown reason (no return data)";

        // Slice out the first 4 bytes (selector) and next 32 bytes (string length location)
        // Then extract the string data
        assembly {
            data := add(data, 0x04) // Skip the first 4 bytes (selector)
        }

        uint256 offset;
        uint256 length;

        assembly {
            offset := mload(data) // First 32 bytes contain the offset
            length := mload(add(data, offset)) // Length of the string at offset
        }

        if (length == 0) return "Unknown reason (empty string)";

        bytes memory stringData = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            stringData[i] = data[offset + 32 + i];
        }

        return string(stringData);
    }
}
