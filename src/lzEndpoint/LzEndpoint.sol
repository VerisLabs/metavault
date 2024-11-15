// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OApp, MessagingFee, Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OAppOptionsType3} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {ISharePriceOracle} from "../SharePriceOracle/ISharePriceOracle.sol";
import {ILzEndpoint} from "./ILzEndpoint.sol";
import "./../lib/MsgCodec.sol";

/**
 * @title LzEndpoint
 * @notice Contract for managing cross-chain communication of vault share prices
 * @dev Implements OApp, OAppOptionsType3, and ILzEndpoint
 */
contract LzEndpoint is OApp, OAppOptionsType3, ILzEndpoint {
    using MsgCodec for *;
    using OptionsBuilder for bytes;

    uint8 private constant AB_TYPE = 1;
    uint8 private constant ABA_TYPE = 2;

    ISharePriceOracle public immutable oracle;

    /**
     * @notice Constructs the LzEndpoint contract
     * @param _endpoint The LayerZero endpoint address
     * @param _owner The owner of the contract
     * @param _oracle The SharePriceOracle contract address
     */
    constructor(
        address _endpoint,
        address _owner,
        address _oracle
    ) OApp(_endpoint, _owner) Ownable(_owner) {
        oracle = ISharePriceOracle(_oracle);
        
    }

    // /** @inheritdoc ILzEndpoint */
    function quoteVaultAddresses(
        uint32 _dstEid,
        uint16 _msgType,
        address[] calldata _message,
        bytes calldata _extraSendOptions,
        bytes calldata _extraReturnOptions,
        bool _payInLzToken
    ) public view override returns (MessagingFee memory fee) {
        bytes memory payload = MsgCodec.encodeVaultAddresses(
            _msgType,
            _message,
            _extraReturnOptions
        );
        bytes memory options = combineOptions(
            _dstEid,
            _msgType,
            _extraSendOptions
        );

        return _quote(_dstEid, payload, options, _payInLzToken);
    }

    // /** @inheritdoc ILzEndpoint */
    function quoteVaultReports(
        uint32 _dstEid,
        uint8 _msgType,
        MsgCodec.VaultReport[] calldata _message,
        bytes calldata _extraSendOptions,
        bytes calldata _extraReturnOptions,
        bool _payInLzToken
    ) public view override returns (MessagingFee memory fee) {
        bytes memory payload = MsgCodec.encodeVaultReports(
            _msgType,
            _message,
            _extraReturnOptions
        );
        bytes memory options = combineOptions(
            _dstEid,
            _msgType,
            _extraSendOptions
        );
        return _quote(_dstEid, payload, options, _payInLzToken);
    }

    // /** @inheritdoc ILzEndpoint */
    function sendSharePrices(
        uint32 _dstEid,
        address[] memory _vaultAddresses,
        bytes calldata _options
    ) external payable override {
        MsgCodec.VaultReport[] memory vaultReports = oracle.getSharePrices(
            _vaultAddresses
        );
        bytes memory payload = MsgCodec.encodeVaultReports(
            AB_TYPE,
            vaultReports,
            _options
        );
        bytes memory options = combineOptions(_dstEid, AB_TYPE, _options);

        _lzSend(
            _dstEid,
            payload,
            options,
            MessagingFee(msg.value, 0),
            payable(msg.sender)
        );

        emit VaultReportsSent(_dstEid, vaultReports);

    }

    // /** @inheritdoc ILzEndpoint */
    function requestSharePrices(
        uint32 _dstEid,
        address[] memory _vaultAddresses,
        bytes calldata _extraSendOptions,
        bytes calldata _extraReturnOptions
    ) external payable override {
        bytes memory payload = MsgCodec.encodeVaultAddresses(
            ABA_TYPE,
            _vaultAddresses,
            _extraReturnOptions
        );
        bytes memory options = combineOptions(
            _dstEid,
            ABA_TYPE,
            _extraSendOptions
        );

        _lzSend(
            _dstEid,
            payload,
            options,
            MessagingFee(msg.value, 0),
            payable(msg.sender)
        );

        emit VaultAddressesSent(_dstEid, _vaultAddresses);
    }

    /**
     * @notice Handles incoming messages from other chains
     * @param _origin The origin information of the message
     * @param _message The received message
     * @dev This function is called by the LayerZero endpoint when a message is received
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 /*guid*/,
        bytes calldata _message,
        address,
        bytes calldata
    ) internal override {
        uint16 msgType = MsgCodec.decodeMsgType(_message);

        if (msgType == AB_TYPE) {
            _handleSharePricesUpdate(_origin, _message);
        } else if (msgType == ABA_TYPE) {
            _handleSharePricesRequest(_origin, _message);
        } else {
            revert InvalidMessageType();
        }
    }

    /**
     * @notice Handles the update of share prices received from another chain
     * @param _origin The origin information of the message
     * @param _message The received message containing share prices
     */
    function _handleSharePricesUpdate(
        Origin calldata _origin,
        bytes calldata _message
    ) private {
        (, MsgCodec.VaultReport[] memory vaultReports, , ) = MsgCodec
            .decodeVaultReports(_message);
        oracle.updateSharePrices(_origin.srcEid, vaultReports);
    }

    /**
     * @notice Handles the request for share prices from another chain
     * @param _origin The origin information of the message
     * @param _message The received message containing the request for share prices
     */
    function _handleSharePricesRequest(
        Origin calldata _origin,
        bytes calldata _message
    ) private {
        (
            ,
            address[] memory vaultAddresses,
            uint256 extraOptionsStart,
            uint256 extraOptionsLength
        ) = MsgCodec.decodeVaultAddresses(_message);

        MsgCodec.VaultReport[] memory vaultReports = oracle.getSharePrices(
            vaultAddresses
        );
        bytes memory _options = combineOptions(
            _origin.srcEid,
            AB_TYPE,
            _message[extraOptionsStart:extraOptionsStart + extraOptionsLength]
        );

        _lzSend(
            _origin   .srcEid,
            abi.encode(AB_TYPE, vaultReports),
            _options,
            MessagingFee(msg.value, 0),
            payable(address(this))
        );
    }

    // /** @inheritdoc ILzEndpoint */
    receive() external payable override {}
}
