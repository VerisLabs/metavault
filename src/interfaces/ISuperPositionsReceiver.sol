// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

/// @title ISuperPositionsReceiver
/// @notice Interface for the cross-chain recovery contract for failed SuperPosition investments
/// @dev This interface defines all public and external functions of the SuperPositionsReceiver contract
interface ISuperPositionsReceiver {
    /// @notice Emitted when a token bridge operation is initiated
    /// @param _token Address of the token being bridged
    /// @param _amount Amount of tokens being bridged
    event BridgeInitiated(address _token, uint256 _amount);

    /// @notice Error thrown when attempting to recover funds on the source chain
    error SourceChainRecoveryNotAllowed();

    /// @notice Gets the current source chain ID
    /// @return The chain ID of the source chain where the gateway is deployed
    function sourceChain() external view returns (uint64);

    /// @notice Gets the gateway contract address
    /// @return The address of the SuperformGateway contract
    function gateway() external view returns (address);

    /// @notice Gets the SuperPositions contract address
    /// @return The address of the SuperPositions (ERC1155) contract
    function superPositions() external view returns (address);

    /// @notice Gets the maximum gas limit for bridge calls
    /// @return The maximum gas limit for bridge transactions
    function maxBridgeGasLimit() external view returns (uint256);

    /// @notice Gets the constant for admin role
    /// @return The role identifier for admin privileges
    function ADMIN_ROLE() external view returns (uint256);

    /// @notice Gets the constant for recovery role
    /// @return The role identifier for recovery admin privileges
    function RECOVERY_ROLE() external view returns (uint256);

    /// @notice Updates the gateway contract address
    /// @dev Only callable by addresses with ADMIN_ROLE
    /// @param _gateway New gateway contract address
    function setGateway(address _gateway) external;

    /// @notice Updates the maximum gas limit for bridge calls
    /// @dev Only callable by addresses with ADMIN_ROLE
    /// @param _maxGasLimit New maximum gas limit
    function setMaxBridgeGasLimit(uint256 _maxGasLimit) external;

    /// @notice Recovers stuck tokens from failed cross-chain operations
    /// @dev Can only be called by addresses with RECOVERY_ROLE and only on destination chains
    /// @param token The address of the token to recover
    /// @param amount The amount of tokens to recover
    function recoverFunds(address token, uint256 amount) external;

    /// @notice Checks if the contract supports a given interface
    /// @dev Used for ERC1155 interface detection
    /// @param interfaceId The interface identifier, as specified in ERC-165
    /// @return isSupported True if the contract supports the interface, false otherwise
    function supportsInterface(bytes4 interfaceId) external pure returns (bool isSupported);

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
    ) external returns (bytes4);

    /// @notice Handles the receipt of multiple ERC1155 token types
    /// @dev This function is called at the end of a `safeBatchTransferFrom` after the balances have been updated
    /// @param operator The address which initiated the batch transfer (i.e. msg.sender)
    /// @param from The address which previously owned the tokens
    /// @param superformIds An array containing ids of each token being transferred (order and length must match values array)
    /// @param values An array containing amounts of each token being transferred (order and length must match ids array)
    /// @param data Additional data with no specified format
    /// @return bytes4 `bytes4(keccak256("onERC1155BatchReceived(address,address,uint[],uint[],bytes)"))`
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] memory superformIds,
        uint256[] memory values,
        bytes memory data
    ) external returns (bytes4);

    /// @notice Bridges ERC20 tokens using provided API data
    /// @dev Only callable by addresses with ADMIN_ROLE
    /// @param _to Target address for the bridge transaction (txTarget from API)
    /// @param _txData Transaction data for the bridge (txData from API)
    /// @param _token Address of the token to bridge
    /// @param _allowanceTarget Approval target for the token (approvalData.allowanceTarget from API)
    /// @param _amount Amount of tokens to bridge (approvalData.minimumApprovalAmount from API)
    function bridgeToken(
        address payable _to,
        bytes memory _txData,
        address _token,
        address _allowanceTarget,
        uint256 _amount
    ) external;

    // For OwnableRoles functions we should include them or inherit the interface
    // Assuming we need to interact with role management

    /// @notice Checks if an address has all specified roles
    /// @param user The address to check
    /// @param roles The roles to check for
    /// @return True if the address has all specified roles, false otherwise
    function hasAllRoles(address user, uint256 roles) external view returns (bool);

    /// @notice Grants roles to an address
    /// @param user The address to grant roles to
    /// @param roles The roles to grant
    function grantRoles(address user, uint256 roles) external;

    /// @notice Revokes roles from an address
    /// @param user The address to revoke roles from
    /// @param roles The roles to revoke
    function revokeRoles(address user, uint256 roles) external;
}