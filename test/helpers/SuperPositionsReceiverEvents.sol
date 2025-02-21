// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract SuperPositionsReceiverEvents {
    /// @notice Event emitted when a token is approved for spending
    event TokenApproval(address indexed token, address indexed spender, uint256 amount);
}
