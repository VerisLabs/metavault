// SPDX-License-Identifer: MIT
pragma solidity 0.8.19;

import { ERC4626 } from "solady/tokens/ERC4626.sol";

/// @notice A struct describing the status of a underlying vault
struct VaultData {
    /// @dev id of chain where vault is deployed
    uint64 chainId;
    /// @dev last cached price per ERC4626 shares
    uint192 sharePrice;
    /// @dev superform id of that vault in Superform
    uint256 superformId;
    /// @dev assets invested in that vault
    uint128 totalDebt;
    /// @dev address of the vault
    address vaultAddress;
    /// @dev decimals of the ERC4626 shares
    uint8 decimals;
}

/// @notice helper library to define {VaultData} methods
library VaultLib {
    /// @notice simulates the ERC4626 {convertToAssets} frunction given a vault data
    /// @param self vault data
    /// @param shares amount of shares to convert
    /// @return assets
    function convertToAssets(VaultData memory self, uint256 shares) internal view returns (uint256 assets) {
        if (self.chainId != _chainId()) {
            return self.sharePrice * shares / 10 ** self.decimals;
        } else {
            // If its on this chain fetch share price directly
            return ERC4626(self.vaultAddress).convertToAssets(shares);
        }
    }

    /// @notice simulates the ERC4626 {convertToShares} frunction given a vault data
    /// @param self vault data
    /// @param assets amount of assets to convert
    /// @return shares
    function convertToShares(VaultData memory self, uint256 assets) internal view returns (uint256 shares) {
        if (self.chainId != _chainId()) {
            return assets * 10 ** self.decimals / self.sharePrice;
        } else {
            // If its on this chain fetch share price directly
            return ERC4626(self.vaultAddress).convertToShares(assets);
        }
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
