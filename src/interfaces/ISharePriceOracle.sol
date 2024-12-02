// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct VaultReport {
    uint256 sharePrice;
    uint64 lastUpdate;
    uint32 chainId;
    address reporter;
    address vaultAddress;
}

interface ISharePriceOracle {
    event SharePriceUpdated(uint32 indexed srcChainId, address indexed vault, uint256 price, address reporter);

    event LzEndpointUpdated(address oldEndpoint, address newEndpoint);

    event RoleGranted(address account, uint256 role);

    event RoleRevoked(address account, uint256 role);

    error InvalidAdminAddress();

    error ZeroAddress();

    error InvalidRole();

    error InvalidChainId(uint32 receivedChainId);

    error InvalidReporter();

    function chainId() external view returns (uint32);

    function ADMIN_ROLE() external view returns (uint256);

    function ENDPOINT_ROLE() external view returns (uint256);

    function hasRole(address account, uint256 role) external view returns (bool);

    function getRoles(address account) external view returns (uint256);

    function getSharePrices(address[] calldata vaultAddresses) external view returns (VaultReport[] memory);

    function getStoredSharePrices(
        uint32 _srcChainId,
        address[] calldata _vaultAddresses
    )
        external
        view
        returns (VaultReport[] memory);

    function updateSharePrices(uint32 _srcChainId, VaultReport[] calldata _reports) external;

    function grantRole(address account, uint256 role) external;

    function revokeRole(address account, uint256 role) external;

    function setLzEndpoint(address _endpoint) external;
}
