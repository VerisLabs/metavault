// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { MsgCodec } from "../lib/MsgCodec.sol";
import "../interfaces/ISharePriceOracle.sol";
import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { ERC4626 } from "solady/tokens/ERC4626.sol";

contract SharePriceOracle is ISharePriceOracle, OwnableRoles {
    using MsgCodec for *;

    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                           ///
    ////////////////////////////////////////////////////////////////

    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant ENDPOINT_ROLE = _ROLE_1;

    ////////////////////////////////////////////////////////////////
    ///                      STATE VARIABLES                       ///
    ////////////////////////////////////////////////////////////////

    uint32 public immutable override chainId;
    mapping(uint32 => mapping(address => MsgCodec.VaultReport)) public override sharePrices;
    address private lzEndpoint;

    ////////////////////////////////////////////////////////////////
    ///                       MODIFIERS                           ///
    ////////////////////////////////////////////////////////////////

    modifier onlyEndpoint() {
        _checkRoles(ENDPOINT_ROLE);
        _;
    }

    modifier onlyAdmin() {
        _checkRoles(ADMIN_ROLE);
        _;
    }

    constructor(uint32 _chainId, address _admin) {
        if (_admin == address(0)) revert InvalidAdminAddress();

        chainId = _chainId;

        // Initialize roles
        _initializeOwner(_admin);
        _grantRoles(_admin, ADMIN_ROLE);

        emit OwnershipTransferred(address(0), _admin);
    }

    function setLzEndpoint(address _endpoint) external onlyAdmin {
        if (_endpoint == address(0)) revert ZeroAddress();
        address oldEndpoint = lzEndpoint;
        lzEndpoint = _endpoint;
        _grantRoles(_endpoint, ENDPOINT_ROLE);
        emit LzEndpointUpdated(oldEndpoint, _endpoint);
        emit RoleGranted(_endpoint, ENDPOINT_ROLE);
    }

    function grantRole(address account, uint256 role) external onlyAdmin {
        if (account == address(0)) revert ZeroAddress();
        if (role == 0) revert InvalidRole();

        _grantRoles(account, role);
        emit RoleGranted(account, role);
    }

    function revokeRole(address account, uint256 role) external onlyAdmin {
        if (account == address(0)) revert ZeroAddress();
        if (role == 0) revert InvalidRole();

        _removeRoles(account, role);
        emit RoleRevoked(account, role);
    }

    function hasRole(address account, uint256 role) public view returns (bool) {
        return hasAnyRole(account, role);
    }

    function getRoles(address account) external view returns (uint256) {
        return rolesOf(account);
    }

    function getSharePrices(address[] memory vaultAddresses)
        public
        view
        override
        returns (MsgCodec.VaultReport[] memory)
    {
        MsgCodec.VaultReport[] memory reports = new MsgCodec.VaultReport[](vaultAddresses.length);

        for (uint256 i = 0; i < vaultAddresses.length; i++) {
            ERC4626 vault = ERC4626(vaultAddresses[i]);
            reports[i] = MsgCodec.VaultReport({
                lastUpdate: uint64(block.timestamp),
                chainId: chainId,
                vaultAddress: vaultAddresses[i],
                sharePrice: vault.convertToAssets(10 ** vault.decimals())
            });
        }

        return reports;
    }

    function updateSharePrices(
        uint32 _srcChainId,
        MsgCodec.VaultReport[] memory _vaultReports
    )
        external
        override
        onlyEndpoint
    {
        address[] memory vaults = new address[](_vaultReports.length);
        uint256[] memory prices = new uint256[](_vaultReports.length);

        for (uint256 i = 0; i < _vaultReports.length; i++) {
            sharePrices[_srcChainId][_vaultReports[i].vaultAddress] = _vaultReports[i];
            vaults[i] = _vaultReports[i].vaultAddress;
            prices[i] = _vaultReports[i].sharePrice;
        }

        emit SharePricesUpdated(_srcChainId, vaults, prices);
    }

    function getStoredSharePrices(
        uint32 _srcChainId,
        address[] memory _vaultAddresses
    )
        public
        view
        override
        returns (MsgCodec.VaultReport[] memory reports)
    {
        reports = new MsgCodec.VaultReport[](_vaultAddresses.length);

        for (uint256 i = 0; i < _vaultAddresses.length; i++) {
            reports[i] = sharePrices[_srcChainId][_vaultAddresses[i]];
        }

        return reports;
    }
}
