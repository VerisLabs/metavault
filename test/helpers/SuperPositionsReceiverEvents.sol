// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;


contract SuperPositionsReceiverEvents {
    /// @notice Event emitted when tokens are successfully bridged
    /// @param token The address of the token being bridged
    /// @param amount The amount of tokens bridged
    event BridgeInitiated(address indexed token, uint256 amount);

    /// @notice Event emitted when a token is approved for spending
    /// @param token The address of the approved token
    /// @param spender The address of the spender
    /// @param amount The approved token amount
    event TokenApproval(address indexed token, address indexed spender, uint256 amount);
}
