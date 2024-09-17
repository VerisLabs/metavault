/// SPDX-License-Identifer: MIT
pragma solidity 0.8.19;

import { ERC4626 } from "solady/tokens/ERC4626.sol";

struct VaultData {
    uint64 chainId;
    uint192 sharePrice;
    uint256 superformId;
    uint128 totalDebt;
    address vaultAddress;
    uint8 decimals;
}

library VaultLib {
    function convertToAssets(VaultData memory self, uint256 shares) internal view returns (uint256) {
        if (self.chainId != _chainId()) {
            return self.sharePrice * shares / 10 ** self.decimals;
        } else {
            return ERC4626(self.vaultAddress).convertToAssets(shares);
        }
    }

    function convertToShares(VaultData memory self, uint256 assets) internal view returns (uint256) {
        if (self.chainId != _chainId()) {
            return assets * 10 ** self.decimals / self.sharePrice;
        } else {
            return ERC4626(self.vaultAddress).convertToShares(assets);
        }
    }

    function _chainId() internal view returns (uint64) {
        return uint64(block.chainid);
    }
}

struct VaultReport {
    uint64 chainId;
    uint192 sharePrice;
    address vaultAddress;
}
