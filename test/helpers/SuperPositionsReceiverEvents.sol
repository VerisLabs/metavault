// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;


contract SuperPositionsReceiverEvents {
    /// @notice Event emitted when a token is approved for spending
    event TokenApproval(address indexed token, address indexed spender, uint256 amount);

    /// @notice Emitted when a token bridge operation is initiated
    /// @param _token Address of the token being bridged
    /// @param _amount Amount of tokens being bridged
    event BridgeInitiated(address _token, uint256 _amount);
}
