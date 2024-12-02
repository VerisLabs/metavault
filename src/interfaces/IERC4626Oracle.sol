// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { VaultReport } from "../types/VaultTypes.sol";
import { MsgCodec } from "lib/MsgCodec.sol";

interface IERC4626Oracle {
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

    function getStoredSharePrices(
        uint64 _srcChainId,
        address[] memory _vaultAddresses
    )
        external
        view
        returns (VaultReport[] memory reports);

    function grantRole(address account, uint256 role) external;

    function revokeRole(address account, uint256 role) external;

    function updateSharePrices(uint64 _srcChainId, VaultReport[] memory _vaultReports) external;
}
