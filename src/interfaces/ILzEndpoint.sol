// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { MsgCodec } from "../lib/MsgCodec.sol";
import { MessagingFee, Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

/**
 * @title ILzEndpoint
 * @notice Interface for the LZEndpoint contract
 * @dev Defines the external functions, events, and errors for the LZEndpoint contract
 */
interface ILzEndpoint {
    /**
     * @notice Emitted when vault addresses are sent to another chain
     * @param dstChainId The destination chain ID
     * @param vaults Array of vault addresses sent
     */
    event VaultAddressesSent(uint32 dstChainId, address[] vaults);

    /**
     * @notice Emitted when vault addresses are received from another chain
     * @param dstChainId The destination chain ID
     * @param reports Array of share price reports received
     */
    event VaultReportsSent(uint32 dstChainId, MsgCodec.VaultReport[] reports);

    /**
     * @notice Emitted when share prices are sent to another chain
     * @param dstEid The destination chain ID
     * @param vaultAddresses Array of vault addresses for which prices are sent
     * @param messageFee Fee paid for the message
     */
    event SharePricesSent(uint32 indexed dstEid, address[] vaultAddresses, uint256 messageFee);

    /**
     * @notice Emitted when share prices are received from another chain
     * @param srcEid The source chain ID
     * @param vaultReports Array of vault reports containing price data
     */
    event SharePricesReceived(uint32 indexed srcEid, MsgCodec.VaultReport[] vaultReports);

    /**
     * @notice Emitted when share prices are requested from another chain
     * @param dstEid The destination chain ID
     * @param vaultAddresses Array of vault addresses for which prices are requested
     * @param messageFee Fee paid for the request
     */
    event SharePricesRequested(uint32 indexed dstEid, address[] vaultAddresses, uint256 messageFee);

    /**
     * @notice Emitted when a share price request is received from another chain
     * @param srcEid The source chain ID
     * @param vaultAddresses Array of requested vault addresses
     */
    event SharePricesRequestReceived(uint32 indexed srcEid, address[] vaultAddresses);

    /**
     * @notice Emitted when a message is processed
     * @param srcEid The source chain ID
     * @param msgType The type of message processed
     * @param guid The unique identifier of the message
     */
    event MessageProcessed(uint32 indexed srcEid, uint16 msgType, bytes32 guid);

    /**
     * @notice Emitted when an error occurs
     * @param message The error message
     * @param reason The reason for the error
     */
    event ErrorOccurred(string message, string reason);

    /**
     * @notice Error thrown when an operation is not authorized
     */
    error Unauthorized();

    /**
     * @notice Error thrown when an invalid destination chain ID is provided
     */
    error InvalidDestination();

    /**
     * @notice Error thrown when an invalid message type is provided
     */
    error InvalidMessageType();

    /**
     * @notice Quotes the fee for sending a message with vault addresses
     * @param _dstEid The destination chain ID
     * @param _msgType The message type
     * @param _message Array of vault addresses
     * @param _extraSendOptions Extra options for sending
     * @param _extraReturnOptions Extra options for returning
     * @param _payInLzToken Whether to pay in LZ tokens
     * @return fee The messaging fee
     */
    function quoteVaultAddresses(
        uint32 _dstEid,
        uint16 _msgType,
        address[] calldata _message,
        bytes calldata _extraSendOptions,
        bytes calldata _extraReturnOptions,
        bool _payInLzToken
    )
        external
        view
        returns (MessagingFee memory fee);

    /**
     * @notice Quotes the fee for sending a message with vault reports
     * @param _dstEid The destination chain ID
     * @param _msgType The message type
     * @param _message Array of VaultReport structs
     * @param _extraSendOptions Extra options for sending
     * @param _extraReturnOptions Extra options for returning
     * @param _payInLzToken Whether to pay in LZ tokens
     * @return fee The messaging fee
     */
    function quoteVaultReports(
        uint32 _dstEid,
        uint8 _msgType,
        MsgCodec.VaultReport[] calldata _message,
        bytes calldata _extraSendOptions,
        bytes calldata _extraReturnOptions,
        bool _payInLzToken
    )
        external
        view
        returns (MessagingFee memory fee);

    /**
     * @notice Sends share prices to another chain
     * @param _dstEid The destination chain ID
     * @param _vaultAddresses Array of vault addresses
     * @param _options Additional options for the transaction
     */
    function sendSharePrices(
        uint32 _dstEid,
        address[] memory _vaultAddresses,
        bytes calldata _options
    )
        external
        payable;

    /**
     * @notice Requests share prices from another chain
     * @param _dstEid The destination chain ID
     * @param _vaultAddresses Array of vault addresses to request prices for
     * @param _extraSendOptions Extra options for sending
     * @param _extraReturnOptions Extra options for returning
     */
    function requestSharePrices(
        uint32 _dstEid,
        address[] memory _vaultAddresses,
        bytes calldata _extraSendOptions,
        bytes calldata _extraReturnOptions
    )
        external
        payable;

    /**
     * @notice Fallback function to receive Ether
     */
    receive() external payable;
}
