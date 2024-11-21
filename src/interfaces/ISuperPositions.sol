/// SPDX-License-Identifer: MIT
pragma solidity ^0.8.19;

import { IERC1155A } from "./IERC1155A.sol";

/// @title ISuperPositions
/// @dev Interface for SuperPositions
/// @author Zeropoint Labs
interface ISuperPositions is IERC1155A {
    //////////////////////////////////////////////////////////////
    //              EXTERNAL WRITE FUNCTIONS                    //
    //////////////////////////////////////////////////////////////

    /// @dev allows minter to mint shares on source
    /// @param receiverAddress_ is the beneficiary of shares
    /// @param id_ is the id of the shares
    /// @param amount_ is the amount of shares to mint
    function mintSingle(address receiverAddress_, uint256 id_, uint256 amount_) external;

    /// @dev allows minter to mint shares on source in batch
    /// @param receiverAddress_ is the beneficiary of shares
    /// @param ids_ are the ids of the shares
    /// @param amounts_ are the amounts of shares to mint
    function mintBatch(address receiverAddress_, uint256[] memory ids_, uint256[] memory amounts_) external;

    /// @dev allows superformRouter to burn shares on source
    /// @notice burn is done optimistically by the router in the beginning of the withdraw transactions
    /// @notice in case the withdraw tx fails on the destination, shares are reminted through stateSync
    /// @param srcSender_ is the address of the sender
    /// @param id_ is the id of the shares
    /// @param amount_ is the amount of shares to burn
    function burnSingle(address srcSender_, uint256 id_, uint256 amount_) external;

    /// @dev allows burner to burn shares on source in batch
    /// @param srcSender_ is the address of the sender
    /// @param ids_ are the ids of the shares
    /// @param amounts_ are the amounts of shares to burn
    function burnBatch(address srcSender_, uint256[] memory ids_, uint256[] memory amounts_) external;
}
