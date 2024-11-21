// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { VaultReport } from "../types/VaultTypes.sol";

/// @title MsgCodec Library
/// @notice A library for encoding and decoding messages used in cross-chain communication
/// @dev This library provides functions to encode and decode vault addresses and reports
library MsgCodec {
    /// @notice Encodes vault addresses along with message type and extra options
    /// @dev This function is used to prepare vault addresses for cross-chain transmission
    /// @param _msgType Type of the message
    /// @param _message Array of vault addresses
    /// @param _extraReturnOptions Extra return options as bytes
    /// @return bytes Encoded message as bytes
    function encodeVaultAddresses(
        uint16 _msgType,
        address[] memory _message,
        bytes memory _extraReturnOptions
    )
        public
        pure
        returns (bytes memory)
    {
        uint256 extraOptionsLength = _extraReturnOptions.length;
        return abi.encode(_msgType, _message, extraOptionsLength, _extraReturnOptions, extraOptionsLength);
    }

    /// @notice Decodes a message containing vault addresses
    /// @dev This function is used to extract vault addresses from a cross-chain message
    /// @param encodedMessage The encoded message
    /// @return msgType Type of the message
    /// @return message Array of decoded vault addresses
    /// @return extraOptionsStart Start index of extra options in the encoded message
    /// @return extraOptionsLength Length of extra options
    function decodeVaultAddresses(bytes calldata encodedMessage)
        public
        pure
        returns (uint16 msgType, address[] memory message, uint256 extraOptionsStart, uint256 extraOptionsLength)
    {
        (msgType, message, extraOptionsLength) = abi.decode(encodedMessage, (uint16, address[], uint256));
        // Calculate the start position of extra options
        extraOptionsStart = 7 * 32 + (message.length * 32);

        return (msgType, message, extraOptionsStart, extraOptionsLength);
    }

    /// @notice Encodes vault reports along with message type and extra options
    /// @dev This function is used to prepare vault reports for cross-chain transmission
    /// @param _msgType Type of the message
    /// @param _message Array of VaultReport structs
    /// @param _extraReturnOptions Extra return options as bytes
    /// @return bytes Encoded message as bytes
    function encodeVaultReports(
        uint16 _msgType,
        VaultReport[] memory _message,
        bytes memory _extraReturnOptions
    )
        public
        pure
        returns (bytes memory)
    {
        uint256 extraOptionsLength = _extraReturnOptions.length;
        return abi.encode(_msgType, _message, extraOptionsLength, _extraReturnOptions, extraOptionsLength);
    }

    /// @notice Decodes a message containing vault reports
    /// @dev This function is used to extract vault reports from a cross-chain message
    /// @param encodedMessage The encoded message
    /// @return msgType Type of the message
    /// @return message Array of decoded VaultReport structs
    /// @return extraOptionsStart Start index of extra options in the encoded message
    /// @return extraOptionsLength Length of extra options
    function decodeVaultReports(bytes calldata encodedMessage)
        public
        pure
        returns (uint16 msgType, VaultReport[] memory message, uint256 extraOptionsStart, uint256 extraOptionsLength)
    {
        bytes memory messageInMemory = encodedMessage;
        (msgType, message, extraOptionsLength) = abi.decode(messageInMemory, (uint16, VaultReport[], uint256));

        extraOptionsStart = 7 * 32 + (message.length * 32);

        return (msgType, message, extraOptionsStart, extraOptionsLength);
    }

    /// @notice Decodes the message type from an encoded message
    /// @dev This function uses assembly to efficiently extract the message type
    /// @param encodedMessage The encoded message
    /// @return msgType Decoded message type
    function decodeMsgType(bytes calldata encodedMessage) public pure returns (uint16 msgType) {
        assembly {
            // Load the first 32 bytes of the calldata
            let word := calldataload(encodedMessage.offset)
            // Extract the last 16 bits (2 bytes)
            msgType := and(word, 0xffff)
        }
    }
}
