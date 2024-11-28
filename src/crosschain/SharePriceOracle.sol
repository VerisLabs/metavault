// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC4626Oracle } from "interfaces/Lib.sol";

import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { VaultReport } from "types/Lib.sol";

contract SharePriceOracle is IERC4626Oracle, OwnableRoles {
    event SharePriceUpdated(uint64 indexed srcChainId, address indexed vault, uint256 price, address reporter);
    event LzEndpointUpdated(address oldEndpoint, address newEndpoint);
    event RoleGranted(address account, uint256 role);
    event RoleRevoked(address account, uint256 role);

    error InvalidAdminAddress();
    error ZeroAddress();
    error InvalidRole();
    error InvalidChainId(uint64 receivedChainId);
    error InvalidReporter();
    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                           ///
    ////////////////////////////////////////////////////////////////

    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant ENDPOINT_ROLE = _ROLE_1;

    ////////////////////////////////////////////////////////////////
    ///                      STATE VARIABLES                       ///
    ////////////////////////////////////////////////////////////////
    uint64 public immutable override chainId;
    address private lzEndpoint;

    mapping(bytes32 => VaultReport[]) public sharePrices;

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

    ////////////////////////////////////////////////////////////////
    ///                     CONSTRUCTOR                           ///
    ////////////////////////////////////////////////////////////////
    constructor(uint64 _chainId, address _admin) {
        if (_admin == address(0)) revert InvalidAdminAddress();
        chainId = _chainId;
        _initializeOwner(_admin);
        _grantRoles(_admin, ADMIN_ROLE);
    }

    ////////////////////////////////////////////////////////////////
    ///                    ADMIN FUNCTIONS                        ///
    ////////////////////////////////////////////////////////////////
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

    ////////////////////////////////////////////////////////////////
    ///                 EXTERNAL FUNCTIONS                       ///
    ////////////////////////////////////////////////////////////////
    function updateSharePrices(uint64 _srcChainId, VaultReport[] calldata reports) external override onlyEndpoint {
        if (_srcChainId == chainId) revert InvalidChainId(_srcChainId);

        uint256 len = reports.length;
        bytes32 key;

        unchecked {
            for (uint256 i; i < len; ++i) {
                VaultReport calldata report = reports[i];
                if (report.chainId != _srcChainId) {
                    revert InvalidChainId(report.chainId);
                }
                //if (report.reporter == address(0)) revert InvalidReporter();

                key = getPriceKey(_srcChainId, report.vaultAddress);
                sharePrices[key].push(report);

                emit SharePriceUpdated(_srcChainId, report.vaultAddress, report.sharePrice, report.reporter);
            }
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                 EXTERNAL VIEW FUNCTIONS                   ///
    ////////////////////////////////////////////////////////////////
    function getSharePrices(address[] memory vaultAddresses) public view override returns (VaultReport[] memory) {
        VaultReport[] memory reports = new VaultReport[](vaultAddresses.length);

        for (uint256 i = 0; i < vaultAddresses.length; i++) {
            ERC4626 vault = ERC4626(vaultAddresses[i]);
            reports[i] = VaultReport({
                lastUpdate: uint64(block.timestamp),
                chainId: chainId,
                vaultAddress: vaultAddresses[i],
                sharePrice: uint192(vault.convertToAssets(10 ** vault.decimals())),
                reporter: msg.sender
            });
        }

        return reports;
    }

    function getStoredSharePrices(
        uint64 _srcChainId,
        address[] calldata _vaultAddresses
    )
        external
        view
        returns (VaultReport[] memory)
    {
        uint256 len = _vaultAddresses.length;
        VaultReport[] memory reports = new VaultReport[](len * 10); // Assuming a max of 10 reports per address
        uint256 reportIndex = 0;

        unchecked {
            for (uint256 i; i < len; ++i) {
                bytes32 key = getPriceKey(_srcChainId, _vaultAddresses[i]);
                VaultReport[] storage vaultReports = sharePrices[key];
                uint256 vaultReportsLen = vaultReports.length;
                for (uint256 j; j < vaultReportsLen; ++j) {
                    reports[reportIndex++] = vaultReports[j];
                }
            }
        }

        return reports;
    }

    function getLatestSharePrice(
        uint64 _srcChainId,
        address _vaultAddress
    )
        external
        view
        returns (VaultReport memory)
    {
        bytes32 key = getPriceKey(_srcChainId, _vaultAddress);
        return sharePrices[key][sharePrices[key].length - 1];
    }

    function getPriceKey(uint64 _srcChainId, address _vault) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_srcChainId, _vault));
    }

    function hasRole(address account, uint256 role) public view returns (bool) {
        return hasAnyRole(account, role);
    }

    function getRoles(address account) external view returns (uint256) {
        return rolesOf(account);
    }
}
