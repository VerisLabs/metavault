/// SPDX-License-Identifer: MIT
pragma solidity 0.8.21;

struct VaultData {
    uint16 chain;
    address vaultAddress;
    uint256 superformId;
    uint256 totalAssets;
    uint256 totalAssetsWithdrawable;
    uint256 debtRatio;
    uint256 totalDebt;
}

struct VaultReport {
    uint16 chainId;
    address vault;
    uint256 totalAssets;
    uint256 totalAssetsWithdrawable;
}
