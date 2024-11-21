// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { VaultReport } from "../types/VaultTypes.sol";
import { MsgCodec } from "lib/MsgCodec.sol";
/**
 * @title IERC4626Oracle
 * @notice Interface for the SharePriceOracle contract
 */
interface IERC4626Oracle {
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function chainId() external view returns (uint64);
    function ADMIN_ROLE() external view returns (uint256);
    function ENDPOINT_ROLE() external view returns (uint256);

    function hasRole(address account, uint256 role) external view returns (bool);
    function getRoles(address account) external view returns (uint256);

    function getSharePrices(address[] memory vaultAddresses) external view returns (VaultReport[] memory);

    function getLatestSharePrice(
        uint64 _srcChainId,
        address _vaultAddress
    )
        external
        view
        returns (VaultReport memory);

    function sharePrices(
        uint64 _srcChainId,
        address _vaultAddress
    )
        external
        view
        returns (uint64 lastUpdate, uint64 chainId, address vaultAddress, uint256 sharePrice);

    function getStoredSharePrices(
        uint64 _srcChainId,
        address[] memory _vaultAddresses
    )
        external
        view
        returns (VaultReport[] memory reports);

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function grantRole(address account, uint256 role) external;
    function revokeRole(address account, uint256 role) external;

    function updateSharePrices(uint64 _srcChainId, VaultReport[] memory _vaultReports) external;
}
