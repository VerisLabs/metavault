/// SPDX-License-Identifer: MIT
pragma solidity ^0.8.19;

import { ISuperPositions, ISuperformGateway } from "interfaces/Lib.sol";

import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

/// @title SuperPositionsReceiver
/// @notice A cross-chain recovery contract for failed SuperPosition investments
/// @dev This contract must be deployed with identical addresses across all chains to handle failed cross-chain
/// operations.
///      It serves as a safety mechanism in the Superform protocol to recover stuck assets from failed investments.
contract SuperPositionsReceiver is OwnableRoles {
    using SafeTransferLib for address;

    error SourceChainRecoveryNotAllowed();

    /// @notice Role identifier for admin privileges
    /// @dev Admins can manage contract configuration and roles
    uint256 public constant ADMIN_ROLE = _ROLE_0;

    /// @notice Role identifier for recovery admin privileges
    /// @dev Recovery admins can execute fund recovery operations
    uint256 public constant RECOVERY_ROLE = _ROLE_1;

    /// @notice The chain ID of the source chain where the gateway is deployed
    /// @dev Used to differentiate between source and destination chain behaviors
    uint64 public sourceChain;

    /// @notice The address of the SuperformGateway contract
    /// @dev Gateway contract that handles cross-chain SuperPosition operations
    address public gateway;

    /// @notice The address of the SuperPositions (ERC1155) contract
    /// @dev Contract that manages the SuperPosition tokens
    address public superPositions;

    /// @notice Initializes the receiver with source chain and contract addresses
    /// @dev Sets up the contract with necessary addresses and grants initial admin roles
    /// @param _sourceChain The chain ID where the original gateway is deployed
    /// @param _gateway Address of the SuperformGateway contract
    /// @param _superPositions Address of the SuperPositions contract
    constructor(uint64 _sourceChain, address _gateway, address _superPositions) {
        sourceChain = _sourceChain;
        gateway = _gateway;
        superPositions = _superPositions;
        // Initialize ownership and grant admin role
        _initializeOwner(msg.sender);
        _grantRoles(msg.sender, ADMIN_ROLE);
    }

    /// @notice Recovers stuck tokens from failed cross-chain operations
    /// @dev Can only be called by addresses with RECOVERY_ROLE and only on destination chains
    /// @param token The address of the token to recover
    /// @param amount The amount of tokens to recover
    function recoverFunds(address token, uint256 amount) external onlyRoles(RECOVERY_ROLE) {
        if (sourceChain == block.chainid) revert SourceChainRecoveryNotAllowed();
        token.safeTransfer(msg.sender, amount);
    }

    /// @dev Supports ERC1155 interface detection
    /// @param interfaceId The interface identifier, as specified in ERC-165
    /// @return isSupported True if the contract supports the interface, false otherwise
    function supportsInterface(bytes4 interfaceId) public pure returns (bool isSupported) {
        if (interfaceId == 0x4e2312e0) return true;
    }

    /// @notice Handles the receipt of a single ERC1155 token type
    /// @dev This function is called at the end of a `safeTransferFrom` after the balance has been updated
    /// @param operator The address which initiated the transfer (i.e. msg.sender)
    /// @param from The address which previously owned the token
    /// @param superformId The ID of the token being transferred
    /// @param value The amount of tokens being transferred
    /// @param data Additional data with no specified format
    /// @return bytes4 `bytes4(keccak256("onERC1155Received(address,address,uint,uint,bytes)"))`
    function onERC1155Received(
        address operator,
        address from,
        uint256 superformId,
        uint256 value,
        bytes memory data
    )
        public
        returns (bytes4)
    {
        // Silence compiler warnings
        operator;
        value;
        data;
        if (sourceChain == block.chainid) {
            if (msg.sender != address(superPositions)) revert();
            if (from != address(0)) revert();
            ISuperPositions(superPositions).safeTransferFrom(address(this), address(gateway), superformId, value, "");
            return this.onERC1155Received.selector;
        }
    }

    /// @notice Handles the receipt of multiple ERC1155 token types
    /// @dev This function is called at the end of a `safeBatchTransferFrom` after the balances have been updated
    /// @param operator The address which initiated the batch transfer (i.e. msg.sender)
    /// @param from The address which previously owned the tokens
    /// @param superformIds An array containing ids of each token being transferred (order and length must match values
    /// array)
    /// @param values An array containing amounts of each token being transferred (order and length must match ids
    /// array)
    /// @param data Additional data with no specified format
    /// @return bytes4 `bytes4(keccak256("onERC1155BatchReceived(address,address,uint[],uint[],bytes)"))`
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] memory superformIds,
        uint256[] memory values,
        bytes memory data
    )
        public
        returns (bytes4)
    {
        // Silence compiler warnings
        operator;
        from;
        values;
        data;
        for (uint256 i = 0; i < superformIds.length; ++i) {
            onERC1155Received(address(0), address(0), superformIds[i], 0, "");
        }
        return this.onERC1155BatchReceived.selector;
    }
}
