// SPDX-License-Identifer: MIT
pragma solidity 0.8.19;

import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { IERC4626Oracle } from "../interfaces/IERC4626Oracle.sol";

uint256 constant ORACLE_STALENESS_TOLERANCE = 8 hours;

/// @notice A struct describing the status of a underlying vault
struct VaultData {
    /// @dev id of chain where vault is deployed
    uint64 chainId;
    /// @dev last reported share price
    uint192 lastReportedSharePrice;
    /// @dev superform id of that vault in Superform
    uint256 superformId;
    /// @dev share price oracle
    IERC4626Oracle oracle;
    /// @dev decimals of the ERC4626 shares
    uint8 decimals;
    /// @dev assets invested in that vault
    uint128 totalDebt;
    /// @dev address of the vault
    address vaultAddress;
}

/// @notice helper library to define {VaultData} methods
library VaultLib {
    /// @notice simulates the ERC4626 {convertToAssets} frunction given a vault data
    /// @param self vault data
    /// @param shares amount of shares to convert
    /// @return assets
    function convertToAssets(
        VaultData memory self,
        uint256 shares,
        bool revertIfStale
    )
        internal
        view
        returns (uint256 assets)
    {
        if (self.chainId != _chainId()) {
            (uint256 sharePrice, uint256 lastUpdated) = self.oracle.getSharePrice(self.vaultAddress);
            if (revertIfStale) {
                if (lastUpdated + ORACLE_STALENESS_TOLERANCE < block.timestamp) revert();
            }
            return sharePrice * shares / 10 ** self.decimals;
        } else {
            // If its on this chain fetch share price directly
            return ERC4626(self.vaultAddress).convertToAssets(shares);
        }
    }

    /// @notice simulates the ERC4626 {convertToAssets} frunction given a vault data
    /// @param self vault data
    /// @param shares amount of shares to convert
    /// @return assets
    function convertToAssetsCachedSharePrice(
        VaultData memory self,
        uint256 shares
    )
        internal
        pure
        returns (uint256 assets)
    {
        return self.lastReportedSharePrice * shares / 10 ** self.decimals;
    }

    /// @notice simulates the ERC4626 {convertToShares} frunction given a vault data
    /// @param self vault data
    /// @param assets amount of assets to convert
    /// @return shares
    function convertToShares(
        VaultData memory self,
        uint256 assets,
        bool revertIfStale
    )
        internal
        view
        returns (uint256 shares)
    {
        if (self.chainId != _chainId()) {
            (uint256 sharePrice, uint256 lastUpdated) = self.oracle.getSharePrice(self.vaultAddress);
            if (revertIfStale) {
                if (lastUpdated + ORACLE_STALENESS_TOLERANCE < block.timestamp) revert();
            }
            return assets * 10 ** self.decimals / sharePrice;
        } else {
            // If its on this chain fetch share price directly
            return ERC4626(self.vaultAddress).convertToShares(assets);
        }
    }

    function sharePrice(VaultData memory self) internal view returns (uint256) {
        if (self.chainId != _chainId()) {
            (uint256 sharePrice,) = self.oracle.getSharePrice(self.vaultAddress);
            return sharePrice;
        } else {
            // If its on this chain fetch share price directly
            return ERC4626(self.vaultAddress).convertToAssets(10 ** self.decimals);
        }
    }

    /// @notice simulates the ERC4626 {convertToShares} frunction given a vault data
    /// @param self vault data
    /// @param assets amount of assets to convert
    /// @return shares
    function convertToSharesCachedSharePrice(
        VaultData memory self,
        uint256 assets
    )
        internal
        view
        returns (uint256 shares)
    {
        return assets * 10 ** self.decimals / self.lastReportedSharePrice;
    }

    /// @dev get chain id
    /// @return chainId
    function _chainId() internal view returns (uint64 chainId) {
        return uint64(block.chainid);
    }
}

/// @notice A struct passed to the vault aggregator
/// to report new data about some vault
struct VaultReport {
    /// @dev source chain id
    uint64 chainId;
    /// @dev last fetched share price
    uint192 sharePrice;
    /// @dev vault address
    address vaultAddress;
}
