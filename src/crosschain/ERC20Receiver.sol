/// SPDX-License-Identifer: MIT
pragma solidity ^0.8.19;

import { ISuperformGateway } from "interfaces/Lib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

contract ERC20Receiver {
    using SafeTransferLib for address;

    address immutable _deployer;
    address immutable _asset;
    address immutable _superPositions;
    bytes32 public key;
    uint256 public minExpectedBalance;

    constructor(address _asset_, address _superPositions_) {
        _asset = _asset_;
        _superPositions = _superPositions_;
        _deployer = msg.sender;
    }

    function balance() external view returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function pull(uint256 amount) external {
        if (msg.sender != _deployer) revert();
        _asset.safeTransfer(_deployer, amount);
    }

    function setMinExpectedBalance(uint256 amount) external {
        if (msg.sender != _deployer) revert();
        minExpectedBalance = amount;
    }

    function initialize(bytes32 _key) external {
        key = _key;
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
        if (msg.sender != address(_superPositions)) revert();
        if (from != address(0)) revert();
        ISuperformGateway(_deployer).notifyRefund(superformId, value);
        return this.onERC1155Received.selector;
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
