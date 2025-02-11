// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import { ModuleBase } from "common/Lib.sol";

import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";

import {
    LiqRequest,
    MultiDstMultiVaultStateReq,
    MultiDstSingleVaultStateReq,
    MultiVaultSFData,
    MultiXChainMultiVaultWithdraw,
    MultiXChainSingleVaultWithdraw,
    ProcessRedeemRequestParams,
    SingleDirectMultiVaultStateReq,
    SingleDirectSingleVaultStateReq,
    SingleVaultSFData,
    SingleXChainMultiVaultStateReq,
    SingleXChainMultiVaultWithdraw,
    SingleXChainSingleVaultStateReq,
    SingleXChainSingleVaultWithdraw,
    VaultData,
    VaultLib
} from "types/Lib.sol";

/// @title ERC7540EngineReader
/// @notice This module is used to read the state of the ERC7540Engine and to preview the withdrawal route
contract ERC7540EngineReader is ModuleBase {
    /// @notice Thrown when attempting to withdraw more assets than are currently available
    error InsufficientAvailableAssets();

    /// @dev Safe transfer operations for ERC20 tokens
    using SafeTransferLib for address;

    /// @dev Library for vault-related operations
    using VaultLib for VaultData;

    /// @notice Simulates a withdrawal route to help relayers determine how to fulfill redemption requests
    /// @dev This is an off-chain helper function that calculates the optimal route for processing
    /// withdrawals across different chains and vaults. It computes:
    /// 1. How much can be fulfilled directly from idle assets
    /// 2. Which vaults need to be accessed for the remaining amount
    /// 3. The distribution of withdrawals across different chains and vaults
    /// The function follows the same withdrawal queue priority as actual withdrawals:
    /// - First uses idle assets
    /// - Then local chain vaults
    /// - Finally cross-chain vaults
    /// @param controller Address of shares owner
    /// @return cachedRoute A struct containing:
    ///         - The withdrawal route across different chains
    ///         - The shares to be redeemed from each vault
    ///         - The assets expected from each withdrawal
    ///         - The amount that can be fulfilled immediately from idle assets
    ///         - Various cached state values needed for processing
    function previewWithdrawalRoute(
        address controller,
        uint256 shares
    )
        public
        view
        returns (ProcessRedeemRequestCache memory cachedRoute)
    {
        if (shares == 0) {
            shares = pendingRedeemRequest(controller);
        }
        cachedRoute.assets = convertToAssets(shares);
        cachedRoute.totalIdle = _totalIdle;
        cachedRoute.totalDebt = _totalDebt;
        cachedRoute.totalAssets = totalAssets();

        // Cannot process more assets than the available
        if (cachedRoute.assets > totalWithdrawableAssets()) {
            revert InsufficientAvailableAssets();
        }

        // If totalIdle can covers the amount fulfill directly
        if (cachedRoute.totalIdle >= cachedRoute.assets) {
            cachedRoute.sharesFulfilled = shares;
            cachedRoute.totalClaimableWithdraw = cachedRoute.assets;
        }
        // Otherwise perform Superform withdrawals
        else {
            // Cache amount to withdraw before reducing totalIdle
            cachedRoute.amountToWithdraw = cachedRoute.assets - cachedRoute.totalIdle;
            // Use totalIdle to fulfill the request
            if (cachedRoute.totalIdle > 0) {
                cachedRoute.totalClaimableWithdraw = cachedRoute.totalIdle;
                cachedRoute.sharesFulfilled = _convertToShares(cachedRoute.totalIdle, cachedRoute.totalAssets);
            }
            ///////////////////////////////// PREVIOUS CALCULATIONS ////////////////////////////////
            _prepareWithdrawalRoute(cachedRoute);
        }
        return cachedRoute;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       PRIVATE FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Internal cache struct to allocate in memory
    struct ProcessRedeemRequestCache {
        // List of vauts to withdraw from on each chain
        uint256[WITHDRAWAL_QUEUE_SIZE][N_CHAINS] dstVaults;
        // List of shares to redeem on each vault in each chain
        uint256[WITHDRAWAL_QUEUE_SIZE][N_CHAINS] sharesPerVault;
        // List of assets to withdraw on each vault in each chain
        uint256[WITHDRAWAL_QUEUE_SIZE][N_CHAINS] assetsPerVault;
        // Cache length of list of each chain
        uint256[N_CHAINS] lens;
        // Assets to divest from other vaults
        uint256 amountToWithdraw;
        // Shares actually used
        uint256 sharesFulfilled;
        // Save assets that were withdrawn instantly
        uint256 totalClaimableWithdraw;
        // Cache totalAssets
        uint256 totalAssets;
        // Cache totalIdle
        uint256 totalIdle;
        // Cache totalDebt
        uint256 totalDebt;
        // Convert shares to assets at current price
        uint256 assets;
        // Whether is a single or multivault withdrawal
        bool isSingleChain;
        bool isMultiChain;
        // Whether is a single or multivault withdrawal
        bool isMultiVault;
    }

    /// @dev Precomputes the withdrawal route following the order of the withdrawal queue
    /// according to the needed assets
    /// @param cache the memory pointer of the cache
    /// @dev writes the route to the cache struct
    ///
    /// Note: First it will try to fulfill the request with idle assets, after that it will
    /// loop through the withdrawal queue and compute the destination chains and vaults on each
    /// destionation chain, plus the shaes to redeem on each vault
    function _prepareWithdrawalRoute(ProcessRedeemRequestCache memory cache) private view {
        // Use the local vaults first
        _exhaustWithdrawalQueue(cache, localWithdrawalQueue, false);
        // Use the crosschain vaults after
        _exhaustWithdrawalQueue(cache, xChainWithdrawalQueue, true);
    }

    /// @notice Internal function to process a withdrawal queue and determine optimal withdrawal routes
    /// @dev Iterates through a withdrawal queue to calculate how to fulfill a withdrawal request across multiple vaults
    /// and chains.
    /// The function:
    /// 1. Processes vaults in queue order until request is fulfilled
    /// 2. Calculates shares to withdraw from each vault
    /// 3. Updates debt tracking
    /// 4. Determines if withdrawal is single/multi chain and single/multi vault
    /// 5. Maintains withdrawal state in the cache structure
    ///
    /// For each vault in the queue:
    /// - Checks maximum withdrawable amount
    /// - Calculates required shares
    /// - Updates chain-specific withdrawal arrays
    /// - Tracks debt reductions
    /// - Updates withdrawal type flags (single/multi chain/vault)
    ///
    /// @param cache Storage structure containing withdrawal state and routing information:
    ///        - dstVaults: Arrays of vault IDs per chain
    ///        - sharesPerVault: Shares to withdraw per vault per chain
    ///        - assetsPerVault: Assets to withdraw per vault per chain
    ///        - lens: Number of vaults to process per chain
    ///        - amountToWithdraw: Remaining assets to withdraw
    ///        - totalDebt: Running total of vault debt
    ///        - isSingleChain/isMultiChain/isMultiVault: Withdrawal type flags
    /// @param queue The withdrawal queue to process (either local or cross-chain)
    /// @param resetValues If true, resets amountToWithdraw when queue is exhausted
    function _exhaustWithdrawalQueue(
        ProcessRedeemRequestCache memory cache,
        uint256[WITHDRAWAL_QUEUE_SIZE] memory queue,
        bool resetValues
    )
        private
        view
    {
        // Cache how many chains we need and how many vaults in each chain
        for (uint256 i = 0; i != WITHDRAWAL_QUEUE_SIZE; i++) {
            // If we exhausted the queue stop
            if (queue[i] == 0) {
                if (resetValues) {
                    // reset values
                    cache.amountToWithdraw = cache.assets - cache.totalIdle;
                }
                break;
            }
            if (resetValues) {
                // If its fulfilled stop
                if (cache.amountToWithdraw == 0) {
                    break;
                }
            }
            // Cache next vault from the withdrawal queue
            VaultData memory vault = vaults[queue[i]];
            // Calcualate the maxWithdraw of the vault
            uint256 maxWithdraw = vault.convertToAssets(_sharesBalance(vault), asset(), true);

            // Dont withdraw more than max
            uint256 withdrawAssets = Math.min(maxWithdraw, cache.amountToWithdraw);
            if (withdrawAssets == 0) continue;
            // Cache chain index
            uint256 chainIndex = chainIndexes[vault.chainId];
            // Cache chain length
            uint256 len = cache.lens[chainIndex];
            // Push the superformId to the last index of the array
            cache.dstVaults[chainIndex][len] = vault.superformId;

            uint256 shares;
            if (cache.amountToWithdraw >= maxWithdraw) {
                uint256 balance = _sharesBalance(vault);
                shares = balance;
            } else {
                shares = vault.convertToShares(withdrawAssets, asset(), true);
            }

            if (shares == 0) continue;
            // Push the shares to redeeem of that vault
            cache.sharesPerVault[chainIndex][len] = shares;
            // Push the assetse to withdraw of that vault
            cache.assetsPerVault[chainIndex][len] = withdrawAssets;
            // Reduce the total debt by no more than the debt of this vault
            uint256 debtReduction = Math.min(vault.totalDebt, withdrawAssets);
            // Reduce totalDebt
            cache.totalDebt -= debtReduction;
            // Reduce needed assets
            cache.amountToWithdraw -= withdrawAssets;

            // Cache whether withdrawal spans multiple chains
            if (vault.chainId != THIS_CHAIN_ID) {
                uint256 numberOfVaults = cache.lens[chainIndex];
                if (numberOfVaults != 0) {
                    if (!cache.isSingleChain) {
                        cache.isSingleChain = true;
                    }

                    if (cache.isSingleChain && !cache.isMultiChain) {
                        cache.isMultiChain = true;
                    }

                    if (numberOfVaults > 1) {
                        cache.isMultiVault = true;
                    }
                }
            }

            // Increase index for iteration
            unchecked {
                cache.lens[chainIndex]++;
            }
        }
    }

    /// @dev Helper function to fetch module function selectors
    function selectors() public pure returns (bytes4[] memory) {
        bytes4[] memory s = new bytes4[](1);
        s[1] = this.previewWithdrawalRoute.selector;
        return s;
    }
}
