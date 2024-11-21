// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { MsgCodec } from "../lib/MsgCodec.sol";
import { VaultReport } from "src/types/Lib.sol";

/**
 * @title IERC4626Oracle
 * @notice Interface for the SharePriceOracle contract
 */
interface IERC4626Oracle {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event SharePricesUpdated(uint32 indexed srcChainId, address[] vaults, uint256[] prices);

    event RoleGranted(address indexed account, uint256 indexed role);
    event RoleRevoked(address indexed account, uint256 indexed role);

    // New events
    event LzEndpointUpdated(address indexed oldEndpoint, address indexed newEndpoint);
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error UnauthorizedEndpoint();
    error ZeroAddress();
    error InvalidRole();
    error InvalidAdminAddress();

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function chainId() external view returns (uint32);
    function ADMIN_ROLE() external view returns (uint256);
    function ENDPOINT_ROLE() external view returns (uint256);

    function hasRole(address account, uint256 role) external view returns (bool);
    function getRoles(address account) external view returns (uint256);

    function getSharePrices(address[] memory vaultAddresses) external view returns (MsgCodec.VaultReport[] memory);

    function getSharePrice(uint64 _srcChainId, address _vaultAddress) external view returns (VaultReport memory);

    function sharePrices(
        uint32 _srcChainId,
        address _vaultAddress
    )
        external
        view
        returns (uint64 lastUpdate, uint32 chainId, address vaultAddress, uint256 sharePrice);

    function getStoredSharePrices(
        uint32 _srcChainId,
        address[] memory _vaultAddresses
    )
        external
        view
        returns (MsgCodec.VaultReport[] memory reports);

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function grantRole(address account, uint256 role) external;
    function revokeRole(address account, uint256 role) external;

    function updateSharePrices(uint32 _srcChainId, MsgCodec.VaultReport[] memory _vaultReports) external;
}
