/// SPDX-License-Identifer: MIT
pragma solidity 0.8.21;

struct VaultData {
    uint64 chainId;
    address vaultAddress;
    uint256 superformId;
    uint256 sharePrice;
    uint256 debtRatio;
    uint256 totalDebt;
    uint256 decimals;
}

library VaultLib {
    function convertToAssets(VaultData memory self, uint256 shares) internal view returns (uint256) {
        return self.sharePrice * shares / self.decimals;
    }

    function convertToShares(VaultData memory self, uint256 assets) internal view returns (uint256) {
        return assets * self.decimals / self.sharePrice;
    }
}

struct VaultReport {
    uint16 chainId;
    address vault;
    uint256 sharePrice;
}
