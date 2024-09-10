/// SPDX-License-Identifer: MIT
pragma solidity 0.8.21;

struct VaultData {
    uint64 chainId;
    uint192 sharePrice;
    uint256 superformId;
    uint128 debtRatio;
    uint128 totalDebt;
    address vaultAddress;
    uint8 decimals;
}

library VaultLib {
    function convertToAssets(VaultData memory self, uint256 shares) internal pure returns (uint256) {
        return self.sharePrice * shares / self.decimals;
    }

    function convertToShares(VaultData memory self, uint256 assets) internal pure returns (uint256) {
        return assets * self.decimals / self.sharePrice;
    }
}

struct VaultReport {
    uint64 chainId;
    uint192 sharePrice;
    address vaultAddress;
}
