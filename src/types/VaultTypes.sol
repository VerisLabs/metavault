// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import { LiqRequest } from "./SuperformTypes.sol";
import { ISharePriceOracle } from "interfaces/ISharePriceOracle.sol";
import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { IBaseRouter } from "src/interfaces/IBaseRouter.sol";

import { IHurdleRateOracle } from "src/interfaces/IHurdleRateOracle.sol";
import { VaultReport } from "src/interfaces/ISharePriceOracle.sol";
import { ISuperPositions } from "src/interfaces/ISuperPositions.sol";
import { ISuperformFactory } from "src/interfaces/ISuperformFactory.sol";
import { ISuperformGateway } from "src/interfaces/ISuperformGateway.sol";

/// @dev The maximum allowable staleness for oracle data before being considered outdated
uint256 constant ORACLE_STALENESS_TOLERANCE = 8 hours;

/// @notice A struct describing the status of an underlying vault
/// @dev Contains data about a vault's chain ID, share price, oracle, and more
struct VaultData {
    /// @dev Fees to deduct when applying performance fees
    uint16 deductedFees;
    /// @dev The ID of the chain where the vault is deployed
    uint64 chainId;
    /// @dev The last reported share price of the vault
    uint192 lastReportedSharePrice;
    /// @dev The superform ID of the vault in the Superform protocol
    uint256 superformId;
    /// @dev The oracle that provides the share price for the vault
    ISharePriceOracle oracle;
    /// @dev The number of decimals used in the ERC4626 shares
    uint8 decimals;
    /// @dev The total assets invested in the vault
    uint128 totalDebt;
    /// @dev The address of the vault
    address vaultAddress;
}

struct VaultConfig {
    address asset;
    string name;
    string symbol;
    uint16 managementFee;
    uint16 performanceFee;
    uint16 oracleFee;
    uint24 sharesLockTime;
    IHurdleRateOracle hurdleRateOracle;
    ISuperPositions superPositions;
    address treasury;
    address signerRelayer;
    address owner;
}

/// @notice A helper library to define methods for handling VaultData
/// @dev Provides methods to simulate conversions between shares and assets for a vault
library VaultLib {
    error StaleSharePrice();
    /// @notice Simulates the ERC4626 {convertToAssets} function using vault data
    /// @param self The vault data to operate on
    /// @param shares The number of shares to convert to assets
    /// @param revertIfStale Whether to revert the transaction if the oracle data is stale
    /// @return assets The equivalent amount of assets for the given shares

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
            VaultReport memory report = self.oracle.getLatestSharePrice(self.chainId, self.vaultAddress);
            (uint256 sharePrice_, uint256 lastUpdated) = (report.sharePrice, report.lastUpdate);
            if (revertIfStale) {
                if (lastUpdated + ORACLE_STALENESS_TOLERANCE < block.timestamp) revert StaleSharePrice();
            }
            return sharePrice_ * shares / 10 ** self.decimals;
        } else {
            // If it's on this chain, fetch the share price directly
            return ERC4626(self.vaultAddress).convertToAssets(shares);
        }
    }

    /// @notice Simulates the ERC4626 {convertToAssets} function using cached share price
    /// @param self The vault data to operate on
    /// @param shares The number of shares to convert to assets
    /// @return assets The equivalent amount of assets for the given shares using cached share price
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

    /// @notice Simulates the ERC4626 {convertToShares} function using vault data
    /// @param self The vault data to operate on
    /// @param assets The number of assets to convert to shares
    /// @param revertIfStale Whether to revert the transaction if the oracle data is stale
    /// @return shares The equivalent amount of shares for the given assets
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
            VaultReport memory report = self.oracle.getLatestSharePrice(self.chainId, self.vaultAddress);
            (uint256 sharePrice_, uint256 lastUpdated) = (report.sharePrice, report.lastUpdate);
            if (revertIfStale) {
                if (lastUpdated + ORACLE_STALENESS_TOLERANCE < block.timestamp) revert();
            }
            return assets * 10 ** self.decimals / sharePrice_;
        } else {
            // If it's on this chain, fetch the share price directly
            return ERC4626(self.vaultAddress).convertToShares(assets);
        }
    }

    /// @notice Retrieves the current share price of the vault
    /// @param self The vault data to operate on
    /// @return The current share price
    function sharePrice(VaultData memory self) internal view returns (uint256) {
        if (self.chainId != _chainId()) {
            VaultReport memory report = self.oracle.getLatestSharePrice(self.chainId, self.vaultAddress);
            (uint256 sharePrice_, uint256 lastUpdated) = (report.sharePrice, report.lastUpdate);
            return sharePrice_;
        } else {
            // If it's on this chain, fetch the share price directly
            return ERC4626(self.vaultAddress).convertToAssets(10 ** self.decimals);
        }
    }

    /// @notice Simulates the ERC4626 {convertToShares} function using cached share price
    /// @param self The vault data to operate on
    /// @param assets The number of assets to convert to shares
    /// @return shares The equivalent amount of shares for the given assets using cached share price
    function convertToSharesCachedSharePrice(
        VaultData memory self,
        uint256 assets
    )
        internal
        pure
        returns (uint256 shares)
    {
        return assets * 10 ** self.decimals / self.lastReportedSharePrice;
    }

    /// @notice Retrieves the current chain ID
    /// @return chainId The current chain ID
    function _chainId() internal view returns (uint64 chainId) {
        return uint64(block.chainid);
    }
}

struct SingleXChainSingleVaultWithdraw {
    uint8[] ambIds;
    uint256 outputAmount;
    uint256 maxSlippage;
    LiqRequest liqRequest;
    bool hasDstSwap;
    uint256 value;
}

struct SingleXChainMultiVaultWithdraw {
    uint8[] ambIds;
    uint256[] outputAmounts;
    uint256[] maxSlippages;
    LiqRequest[] liqRequests;
    bool[] hasDstSwaps;
    uint256 value;
}

struct MultiXChainSingleVaultWithdraw {
    uint8[][] ambIds;
    uint256[] outputAmounts;
    uint256[] maxSlippages;
    LiqRequest[] liqRequests;
    bool[] hasDstSwaps;
    uint256 value;
}

struct MultiXChainMultiVaultWithdraw {
    uint8[][] ambIds;
    uint256[][] outputAmounts;
    uint256[][] maxSlippages;
    LiqRequest[][] liqRequests;
    bool[][] hasDstSwaps;
    uint256 value;
}

struct ProcessRedeemRequestParams {
    address controller;
    SingleXChainSingleVaultWithdraw sXsV;
    SingleXChainMultiVaultWithdraw sXmV;
    MultiXChainSingleVaultWithdraw mXsV;
    MultiXChainMultiVaultWithdraw mXmV;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
}
