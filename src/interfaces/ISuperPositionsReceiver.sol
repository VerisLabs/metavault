// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin-contracts-5.1.0/token/ERC20/IERC20.sol";
import { IERC1271 } from "@openzeppelin-contracts-5.1.0/interfaces/IERC1271.sol";

interface ISuperPositionsReceiver is IERC1271 {
    /// @notice Error for unauthorized recovery attempt on the source chain
    error SourceChainRecoveryNotAllowed();

    /// @notice Error for zero address inputs
    error ZeroAddress();

    /// @notice Role identifier for admin privileges
    function ADMIN_ROLE() external view returns (uint256);

    /// @notice Role identifier for recovery admin privileges
    function RECOVERY_ROLE() external view returns (uint256);

    /// @notice The chain ID of the source chain where the gateway is deployed
    function sourceChain() external view returns (uint64);

    /// @notice The address of the SuperformGateway contract
    function gateway() external view returns (address);

    /// @notice The address of the SuperPositions (ERC1155) contract
    function superPositions() external view returns (address);

    /// @notice The address of the backend signer for signature validation
    function backendSigner() external view returns (address);

    /// @notice Constant value for a valid EIP-1271 signature
    function MAGIC_VALUE() external pure returns (bytes4);

    /// @notice Constant value for an invalid EIP-1271 signature
    function INVALID_SIGNATURE() external pure returns (bytes4);

    /// @notice Updates the Superform gateway address
    /// @param _gateway The new gateway address
    function setGateway(address _gateway) external;

    /// @notice Sets the backend signer for signature verification
    /// @param _backendSigner The new backend signer address
    function setBackendSigner(address _backendSigner) external;

    /// @notice Grants roles to a specified address
    /// @param user The address to grant roles to
    /// @param roles The roles to be granted
    function grantRoles(address user, uint256 roles) external;


    /// @notice Recovers stuck tokens from failed cross-chain operations
    /// @param token The address of the token to recover
    /// @param amount The amount of tokens to recover
    function recoverFunds(address token, uint256 amount) external;

    /// @notice Checks if the contract supports a given interface
    /// @param interfaceId The interface identifier (EIP-165)
    /// @return True if the interface is supported, false otherwise
    function supportsInterface(bytes4 interfaceId) external pure returns (bool);

    /// @notice Handles single ERC1155 token reception
    /// @param operator The address initiating the transfer
    /// @param from The address of the sender
    /// @param superformId The token ID
    /// @param value The token amount
    /// @param data Additional data
    /// @return The selector for ERC1155 handling
    function onERC1155Received(
        address operator,
        address from,
        uint256 superformId,
        uint256 value,
        bytes memory data
    ) external returns (bytes4);

    /// @notice Handles batch ERC1155 token reception
    /// @param operator The address initiating the batch transfer
    /// @param from The address of the sender
    /// @param superformIds An array of token IDs
    /// @param values An array of token amounts
    /// @param data Additional data
    /// @return The selector for ERC1155 batch handling
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] memory superformIds,
        uint256[] memory values,
        bytes memory data
    ) external returns (bytes4);

    /// @notice Checks if a signature is valid per EIP-1271
    /// @param hash The hashed message
    /// @param signature The provided signature
    /// @return The magic value if valid, otherwise an invalid signature value
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4);

    /// @notice Approves a token for spending
    /// @param token The token address
    /// @param spender The spender address
    /// @param amount The approved amount
    function approveToken(address token, address spender, uint256 amount) external;
}
