// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    IERC4626Oracle,
    ILayerZeroEndpointV2,
    ILayerZeroReceiver,
    MessagingFee,
    MessagingParams,
    MessagingReceipt,
    Origin
} from "interfaces/Lib.sol";
import { MsgCodec } from "lib/Lib.sol";
import { VaultReport } from "types/Lib.sol";

/// @title MaxLzEndpoint
/// @notice LayerZero endpoint implementation for cross-chain share price oracle communication
/// @dev Implements ILayerZeroReceiver for handling AB (direct) and ABA (request-response) patterns
/// @author MaxApy Protocol
contract MaxLzEndpoint is ILayerZeroReceiver {
    ////////////////////////////////////////////////////////////////
    ///                         CONSTANTS                         ///
    ////////////////////////////////////////////////////////////////

    /// @notice Protocol version identifiers for LayerZero communication
    uint64 private constant SENDER_VERSION = 1;
    uint64 private constant RECEIVER_VERSION = 2;

    /// @notice Option types and limits for message configuration
    uint16 private constant TYPE_3 = 3; // Advanced messaging pattern support
    uint8 private constant WORKER_ID = 1; // Standard executor identifier
    uint256 public immutable MAX_VAULT_COUNT; // Safety limit for batch operations

    /// @notice Message pattern identifiers
    uint8 private constant AB_TYPE = 1; // Simple send-receive
    uint8 private constant ABA_TYPE = 2; // Request-response pattern

    ////////////////////////////////////////////////////////////////
    ///                      STATE VARIABLES                      ///
    ////////////////////////////////////////////////////////////////

    /// @notice Contract immutable state
    address public immutable owner;
    IERC4626Oracle public immutable oracle;

    /// @notice Contract storage state
    ILayerZeroEndpointV2 public endpoint;
    mapping(bytes32 => bool) public processedMessages;
    mapping(uint32 => mapping(uint16 => bytes)) public enforcedOptions;
    mapping(uint32 eid => bytes32 peer) public peers;

    ////////////////////////////////////////////////////////////////
    ///                          EVENTS                           ///
    ////////////////////////////////////////////////////////////////

    event MessageProcessed(bytes32 indexed guid, bytes message);
    event PeerSet(uint32 indexed eid, bytes32 peer);
    event EndpointUpdated(address indexed oldEndpoint, address indexed newEndpoint);
    event SharePricesUpdated(uint32 indexed dstEid, address[] vaults);
    event SharePricesRequested(uint32 indexed dstEid, address[] vaults);
    event EnforcedOptionsSet(EnforcedOptionParam[] params);
    event VaultReportsSent(uint32 indexed dstEid, VaultReport[] reports);

    ////////////////////////////////////////////////////////////////
    ///                          ERRORS                           ///
    ////////////////////////////////////////////////////////////////

    error Unauthorized();
    error MessageAlreadyProcessed();
    error InvalidMessageValue();
    error InvalidOptionType(uint16 optionType);
    error InvalidOptions(bytes options);
    error OnlyEndpoint();
    error PeerNotSet(uint32 eid);
    error EndpointExists();
    error InvalidInput();
    error InsufficientFunds();
    error ZeroAddress();
    error InvalidFee();

    ////////////////////////////////////////////////////////////////
    ///                         STRUCTS                           ///
    ////////////////////////////////////////////////////////////////

    struct EnforcedOptionParam {
        uint32 eid; // Endpoint ID
        uint16 msgType; // Message type
        bytes options; // LayerZero options
    }

    ////////////////////////////////////////////////////////////////
    ///                        MODIFIERS                          ///
    ////////////////////////////////////////////////////////////////

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier validVaultArray(address[] calldata vaults) {
        if (vaults.length == 0 || vaults.length > MAX_VAULT_COUNT) {
            revert InvalidInput();
        }
        _;
    }

    ////////////////////////////////////////////////////////////////
    ///                      CONSTRUCTOR                          ///
    ////////////////////////////////////////////////////////////////

    /// @notice Initializes the endpoint with owner and oracle addresses
    /// @param owner_ Contract owner address
    /// @param oracle_ Share price oracle contract address
    constructor(address owner_, address lzEndpoint, address oracle_, uint256 maxVaultCount_) {
        if (owner_ == address(0) || oracle_ == address(0)) revert ZeroAddress();
        if (maxVaultCount_ == 0 || maxVaultCount_ > 1000) revert InvalidInput();
        MAX_VAULT_COUNT = maxVaultCount_;
        owner = owner_;
        oracle = IERC4626Oracle(oracle_);
        endpoint = ILayerZeroEndpointV2(lzEndpoint);
    }

    ////////////////////////////////////////////////////////////////
    ///                    ADMIN FUNCTIONS                        ///
    ////////////////////////////////////////////////////////////////

    /// @notice Configures the LayerZero endpoint address
    /// @dev Can only be set once
    function setLzEndpoint(address endpoint_) external onlyOwner {
        if (address(endpoint) != address(0)) revert EndpointExists();
        if (endpoint_ == address(0)) revert InvalidInput();
        endpoint = ILayerZeroEndpointV2(endpoint_);
        emit EndpointUpdated(address(0), endpoint_);
    }

    /// @notice Sets trusted peer for cross-chain communication
    function setPeer(uint32 eid_, bytes32 peer_) external onlyOwner {
        if (peer_ == bytes32(0)) revert InvalidInput();
        peers[eid_] = peer_;
        emit PeerSet(eid_, peer_);
    }

    /// @notice Configures enforced options for message types
    function setEnforcedOptions(EnforcedOptionParam[] calldata params) external onlyOwner {
        uint256 len = params.length;
        for (uint256 i = 0; i < len;) {
            _assertOptionsType3(params[i].options);
            enforcedOptions[params[i].eid][params[i].msgType] = params[i].options;
            unchecked {
                ++i;
            }
        }
        emit EnforcedOptionsSet(params);
    }

    ////////////////////////////////////////////////////////////////
    ///                   EXTERNAL FUNCTIONS                      ///
    ////////////////////////////////////////////////////////////////

    /// @notice Sends vault share prices to another chain
    function sendSharePrices(
        uint32 dstEid,
        address[] calldata vaultAddresses,
        bytes calldata options
    )
        external
        payable
        validVaultArray(vaultAddresses)
    {
        VaultReport[] memory reports = oracle.getLatestSharePrices(vaultAddresses);
        bytes memory message = MsgCodec.encodeVaultReports(AB_TYPE, reports, options);
        bytes memory combinedOptions = _getCombinedOptions(dstEid, AB_TYPE, options);

        MessagingFee memory fee = _quote(dstEid, message, combinedOptions);
        if (msg.value < fee.nativeFee) revert InvalidMessageValue();

        _lzSend(dstEid, message, combinedOptions, fee, msg.sender);
        emit SharePricesUpdated(dstEid, vaultAddresses);
    }

    /// @notice Requests share prices from another chain
    function requestSharePrices(
        uint32 dstEid,
        address[] calldata vaultAddresses,
        bytes calldata options,
        bytes calldata returnOptions
    )
        external
        payable
        validVaultArray(vaultAddresses)
    {
        bytes memory message = MsgCodec.encodeVaultAddresses(ABA_TYPE, vaultAddresses, returnOptions);
        bytes memory combinedOptions = _getCombinedOptions(dstEid, ABA_TYPE, options);

        MessagingFee memory fee = _quote(dstEid, message, combinedOptions);
        if (msg.value < fee.nativeFee) revert InvalidMessageValue();

        _lzSend(dstEid, message, combinedOptions, fee, msg.sender);
        emit SharePricesRequested(dstEid, vaultAddresses);
    }

    ////////////////////////////////////////////////////////////////
    ///                 EXTERNAL VIEW FUNCTIONS                   ///
    ////////////////////////////////////////////////////////////////

    /// @notice Creates new TYPE_3 options
    function newOptions() public pure returns (bytes memory) {
        return abi.encodePacked(TYPE_3);
    }

    /// @notice Adds executor options to existing options
    function addExecutorLzReceiveOption(
        bytes memory _options,
        uint128 _gas,
        uint128 _value
    )
        public
        pure
        returns (bytes memory)
    {
        bytes memory option = _value == 0 ? abi.encodePacked(_gas) : abi.encodePacked(_gas, _value);

        return abi.encodePacked(
            _options,
            WORKER_ID,
            uint16(option.length + 1),
            uint8(1), // OPTION_TYPE_LZRECEIVE
            option
        );
    }

    /// @notice View function for fee estimation
    function estimateFees(
        uint32 dstEid,
        uint16 msgType,
        bytes calldata message,
        bytes calldata options
    )
        external
        view
        returns (uint256 nativeFee)
    {
        bytes memory combinedOptions = _getCombinedOptions(dstEid, msgType, options);
        return _quote(dstEid, message, combinedOptions).nativeFee;
    }

    ////////////////////////////////////////////////////////////////
    ///              LAYERZERO INTERFACE FUNCTIONS               ///
    ////////////////////////////////////////////////////////////////

    /// @inheritdoc ILayerZeroReceiver
    function allowInitializePath(Origin calldata origin) external view override returns (bool) {
        return peers[origin.srcEid] == origin.sender;
    }

    /// @inheritdoc ILayerZeroReceiver
    function nextNonce(uint32, bytes32) external pure override returns (uint64) {
        return 0;
    }

    /// @inheritdoc ILayerZeroReceiver
    function lzReceive(
        Origin calldata origin,
        bytes32 guid,
        bytes calldata message,
        address,
        bytes calldata extraData
    )
        external
        payable
        override
    {
        if (msg.sender != address(endpoint)) revert OnlyEndpoint();
        if (_getPeerOrRevert(origin.srcEid) != origin.sender) {
            revert PeerNotSet(origin.srcEid);
        }
        if (processedMessages[guid]) revert MessageAlreadyProcessed();

        processedMessages[guid] = true;

        uint16 msgType = MsgCodec.decodeMsgType(message);

        if (msgType == AB_TYPE) {
            (, VaultReport[] memory reports,,) = MsgCodec.decodeVaultReports(message);
            oracle.updateSharePrices(reports[0].chainId, reports);
        } else if (msgType == ABA_TYPE) {
            _handleABAResponse(origin, message, extraData);
        }

        emit MessageProcessed(guid, message);
    }

    ////////////////////////////////////////////////////////////////
    ///                  INTERNAL FUNCTIONS                      ///
    ////////////////////////////////////////////////////////////////

    /// @notice Handles ABA pattern response messages
    function _handleABAResponse(Origin calldata origin, bytes calldata message, bytes calldata extraData) private {
        (, address[] memory vaultAddresses, uint256 start, uint256 length) = MsgCodec.decodeVaultAddresses(message);

        VaultReport[] memory reports = oracle.getLatestSharePrices(vaultAddresses);
        bytes memory returnOptions = message[start:start + length];
        bytes memory returnMessage = MsgCodec.encodeVaultReports(AB_TYPE, reports, returnOptions);

        bytes memory options = _getCombinedOptions(origin.srcEid, AB_TYPE, extraData);
        MessagingFee memory fee = _quote(origin.srcEid, returnMessage, options);

        if (address(this).balance < fee.nativeFee) revert InsufficientFunds();
        _lzSend(origin.srcEid, returnMessage, options, fee, address(this));
    }

    /// @notice Gets peer for endpoint or reverts
    function _getPeerOrRevert(uint32 _eid) internal view returns (bytes32) {
        bytes32 peer = peers[_eid];
        if (peer == bytes32(0)) revert PeerNotSet(_eid);
        return peer;
    }

    /// @notice Gets LayerZero message fee quote
    function _quote(
        uint32 _dstEid,
        bytes memory _message,
        bytes memory _options
    )
        internal
        view
        returns (MessagingFee memory)
    {
        return endpoint.quote(
            MessagingParams(_dstEid, _getPeerOrRevert(_dstEid), _message, _options, false), address(this)
        );
    }

    /// @notice Sends message through LayerZero
    function _lzSend(
        uint32 _dstEid,
        bytes memory _message,
        bytes memory _options,
        MessagingFee memory _fee,
        address _refundAddress
    )
        internal
        returns (MessagingReceipt memory)
    {
        if (_fee.nativeFee == 0) revert InvalidFee();
        if (msg.value < _fee.nativeFee) revert InvalidMessageValue();

        return endpoint.send{ value: msg.value }(
            MessagingParams(_dstEid, _getPeerOrRevert(_dstEid), _message, _options, false), _refundAddress
        );
    }

    /// @notice Combines and validates options
    function _getCombinedOptions(
        uint32 _eid,
        uint16 _msgType,
        bytes memory _options
    )
        internal
        view
        returns (bytes memory)
    {
        bytes memory enforced = enforcedOptions[_eid][_msgType];

        if (enforced.length == 0) return _options;
        if (_options.length == 0) return enforced;
        if (_options.length < 2) revert InvalidOptions(_options);

        uint16 optionsType;
        assembly {
            optionsType := mload(add(_options, 2))
        }
        if (optionsType != TYPE_3) revert InvalidOptionType(optionsType);

        bytes memory result = new bytes(enforced.length + _options.length - 2);
        assembly {
            let enforcedLen := mload(enforced)
            let resultPtr := add(result, 32)
            let enforcedPtr := add(enforced, 32)
            let optionsPtr := add(add(_options, 34), 0)

            // Copy enforced options
            for { let i := 0 } lt(i, enforcedLen) { i := add(i, 32) } {
                mstore(add(resultPtr, i), mload(add(enforcedPtr, i)))
            }

            // Copy remaining options (excluding type)
            let remainingLen := sub(mload(_options), 2)
            for { let i := 0 } lt(i, remainingLen) { i := add(i, 32) } {
                mstore(add(add(resultPtr, enforcedLen), i), mload(add(optionsPtr, i)))
            }
        }
        return result;
    }

    /// @notice Validates TYPE_3 options
    function _assertOptionsType3(bytes memory _options) internal pure {
        if (_options.length < 2) revert InvalidOptions(_options);

        uint16 optionsType;
        assembly {
            optionsType := mload(add(_options, 2))
        }
        if (optionsType != TYPE_3) revert InvalidOptions(_options);
    }

    ////////////////////////////////////////////////////////////////
    ///                   FALLBACK FUNCTIONS                      ///
    ////////////////////////////////////////////////////////////////

    receive() external payable { }
}
