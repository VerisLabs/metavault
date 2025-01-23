// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import { ModuleBase } from "common/Lib.sol";

import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

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

/// @title ERC7540Engine
/// @notice Implementation of a ERC4626 multi-vault deposit liquidity engine with cross-chain functionalities
/// @dev Extends ModuleBase contract and implements advanced redeem request processing
contract ERC7540Engine is ModuleBase {
    /// @notice Thrown when attempting to withdraw more assets than are currently available
    error InsufficientAvailableAssets();

    /// @notice Thrown when signature has expired
    error SignatureExpired();

    /// @notice Thrown when signature verification fails
    error InvalidSignature();

    /// @notice Thrown when there are not enough assets to fulfill a request
    error InsufficientAssets();

    /// @dev Emitted when a redeem request is processed
    event ProcessRedeemRequest(address indexed controller, uint256 shares);

    /// @dev Emitted when a redeem request is fulfilled after being processed
    event FulfillRedeemRequest(address indexed controller, uint256 shares, uint256 assets);

    /// @dev Safe casting operations for uint
    using SafeCastLib for uint256;

    /// @dev Safe transfer operations for ERC20 tokens
    using SafeTransferLib for address;

    /// @dev Library for vault-related operations
    using VaultLib for VaultData;

    /// @dev Library for math
    using Math for uint256;

    /// @notice Processes a redemption request for a given controller
    /// @dev This function is restricted to the RELAYER_ROLE and handles asynchronous processing of redemption requests,
    /// including cross-chain withdrawals
    /// @param params redeem request parameters
    function processRedeemRequest(ProcessRedeemRequestParams calldata params)
        external
        payable
        onlyRoles(RELAYER_ROLE)
        nonReentrant
    {
        // Retrieve the pending redeem request for the specified controller
        // This request may involve cross-chain withdrawals from various ERC4626 vaults

        // Process the redemption request asynchronously
        // Parameters:
        // 1. pendingRedeemRequest(controller): Fetches the pending shares
        // 2. controller: The address initiating the redemption (used as both 'from' and 'to')
        _processRedeemRequest(
            ProcessRedeemRequestConfig(
                params.shares == 0 ? pendingRedeemRequest(params.controller) : params.shares,
                params.controller,
                params.sXsV,
                params.sXmV,
                params.mXsV,
                params.mXmV
            )
        );
        // Note: After processing, the redeemed assets are held by this contract
        // The user can later claim these assets using `redeem` or `withdraw`
    }

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
        if (cachedRoute.assets > cachedRoute.totalAssets - gateway.totalpendingXChainInvests()) {
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

    /// @notice Fulfills a settled cross-chain redemption request
    /// @dev Called by the gateway contract when cross-chain assets have been received.
    /// Converts the requested assets to shares and fulfills the redemption request.
    /// Only callable by the gateway contract.
    /// @param controller The address that initiated the redemption request
    /// @param requestedAssets The original amount of assets requested
    /// @param fulfilledAssets The actual amount of assets received after bridging
    function fulfillSettledRequest(address controller, uint256 requestedAssets, uint256 fulfilledAssets) public {
        if (msg.sender != address(gateway)) revert Unauthorized();
        uint256 shares = convertToShares(requestedAssets);
        _fulfillRedeemRequest(shares, fulfilledAssets, controller);
        emit FulfillRedeemRequest(controller, shares, fulfilledAssets);
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
        // Wether is a single chain or multichain withdrawal
        bool isSingleChain;
        bool isMultiChain;
        // Wether is a single or multivault withdrawal
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

            // Cache wether is single chain or multichain
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

    /// @param shares to redeem and burn
    /// @param controller controller that created the request
    /// @param receiver address of the assets receiver in case its a
    struct ProcessRedeemRequestConfig {
        uint256 shares;
        address controller;
        SingleXChainSingleVaultWithdraw sXsV;
        SingleXChainMultiVaultWithdraw sXmV;
        MultiXChainSingleVaultWithdraw mXsV;
        MultiXChainMultiVaultWithdraw mXmV;
    }

    /// @notice Executes the redeem request for a controller
    function _processRedeemRequest(ProcessRedeemRequestConfig memory config) private {
        // Use struct to avoid stack too deep
        ProcessRedeemRequestCache memory cache;
        cache.totalIdle = _totalIdle;
        cache.totalDebt = _totalDebt;
        config.shares = Math.min(balanceOf(address(this)), config.shares);
        cache.assets = convertToAssets(config.shares);
        cache.totalAssets = totalAssets();

        // Cannot process more assets than the
        if (cache.assets > cache.totalAssets - gateway.totalpendingXChainInvests()) {
            revert InsufficientAvailableAssets();
        }

        // If totalIdle can covers the amount fulfill directly
        if (cache.totalIdle >= cache.assets) {
            cache.sharesFulfilled = config.shares;
            cache.totalClaimableWithdraw = cache.assets;
        }
        // Otherwise perform Superform withdrawals
        else {
            // Cache amount to withdraw before reducing totalIdle
            cache.amountToWithdraw = cache.assets - cache.totalIdle;
            // Use totalIdle to fulfill the request
            if (cache.totalIdle > 0) {
                cache.totalClaimableWithdraw = cache.totalIdle;
                cache.sharesFulfilled = _convertToShares(cache.totalIdle, cache.totalAssets);
            }
            ///////////////////////////////// PREVIOUS CALCULATIONS ////////////////////////////////
            _prepareWithdrawalRoute(cache);
            //////////////////////////////// WITHDRAW FROM THIS CHAIN ////////////////////////////////
            // Cache chain index
            uint256 chainIndex = chainIndexes[THIS_CHAIN_ID];
            if (cache.lens[chainIndex] > 0) {
                if (cache.lens[chainIndex] == 1) {
                    // shares to redeem
                    uint256 sharesAmount = cache.sharesPerVault[chainIndex][0];
                    // assets to withdraw
                    uint256 assetsAmount = cache.assetsPerVault[chainIndex][0];
                    // superformId(take first element fo the array)
                    uint256 superformId = cache.dstVaults[chainIndex][0];
                    // get actual withdrawn amount
                    uint256 withdrawn = _liquidateSingleDirectSingleVault(
                        vaults[superformId].vaultAddress, sharesAmount, 0, address(this)
                    );
                    // cache shares to burn
                    cache.sharesFulfilled += _convertToShares(assetsAmount, cache.totalAssets);
                    // reduce vault debt
                    vaults[superformId].totalDebt = _sub0(vaults[superformId].totalDebt, assetsAmount).toUint128();
                    // cache instant total withdraw
                    cache.totalClaimableWithdraw += withdrawn;
                    // Increase idle funds
                    cache.totalIdle += withdrawn;
                } else {
                    uint256 len = cache.lens[chainIndex];
                    // Prepare arguments for request using dynamic arrays
                    address[] memory vaultAddresses = new address[](len);
                    uint256[] memory amounts = new uint256[](len);
                    // Calculate requested amount
                    uint256 requestedAssets;

                    // Cast fixed arrays to dynamic ones
                    for (uint256 i = 0; i != len; i++) {
                        vaultAddresses[i] = vaults[cache.dstVaults[chainIndex][i]].vaultAddress;
                        amounts[i] = cache.sharesPerVault[chainIndex][i];
                        // Reduce vault debt individually
                        uint256 superformId = cache.dstVaults[chainIndex][i];
                        // Increase total assets requested
                        requestedAssets += cache.assetsPerVault[chainIndex][i];
                        // Reduce vault debt
                        vaults[superformId].totalDebt =
                            _sub0(vaults[superformId].totalDebt, cache.assetsPerVault[chainIndex][i]).toUint128();
                    }
                    // Withdraw from the vault synchronously
                    uint256 withdrawn = _liquidateSingleDirectMultiVault(
                        vaultAddresses, amounts, _getEmptyuintArray(amounts.length), address(this)
                    );
                    // Increase claimable assets and fulfilled shares by the amount withdran synchronously
                    cache.totalClaimableWithdraw += withdrawn;
                    cache.sharesFulfilled += _convertToShares(requestedAssets, cache.totalAssets);
                    // Increase total idle
                    cache.totalIdle += withdrawn;
                }
            }

            //////////////////////////////// WITHDRAW FROM EXTERNAL CHAINS ////////////////////////////////
            // If its not multichain
            if (!cache.isMultiChain) {
                // If its multivault
                if (!cache.isMultiVault) {
                    uint256 superformId;
                    uint256 amount;
                    uint64 chainId;
                    uint256 chainIndex;

                    for (uint256 i = 0; i < N_CHAINS; ++i) {
                        if (DST_CHAINS[i] == THIS_CHAIN_ID) continue;
                        // The vaults list length should be 1(single-vault)
                        if (cache.lens[i] > 0) {
                            chainId = DST_CHAINS[i];
                            chainIndex = chainIndexes[chainId];
                            superformId = cache.dstVaults[i][0];
                            amount = cache.sharesPerVault[i][0];

                            // Withdraw from one vault asynchronously(crosschain)
                            _liquidateSingleXChainSingleVault(
                                chainId, superformId, amount, config.controller, config.sXsV, cache.assetsPerVault[i][0]
                            );
                            // reduce vault debt
                            vaults[superformId].totalDebt =
                                _sub0(vaults[superformId].totalDebt, cache.assetsPerVault[chainIndex][0]).toUint128();
                            break;
                        }
                    }
                } else {
                    uint256[] memory superformIds;
                    uint256[] memory amounts;
                    uint64 chainId;
                    for (uint256 i = 0; i < N_CHAINS; ++i) {
                        if (DST_CHAINS[i] == THIS_CHAIN_ID) continue;
                        if (cache.lens[i] > 0) {
                            chainId = DST_CHAINS[i];
                            superformIds = _toDynamicUint256Array(cache.dstVaults[i], cache.lens[i]);
                            amounts = _toDynamicUint256Array(cache.sharesPerVault[i], cache.lens[i]);
                            uint256 totalDebtReduction;
                            // reduce vault debt
                            for (uint256 j = 0; j < superformIds.length;) {
                                vaults[superformIds[j]].totalDebt =
                                    _sub0(vaults[superformIds[j]].totalDebt, cache.assetsPerVault[i][j]).toUint128();
                                totalDebtReduction += cache.assetsPerVault[i][j];
                                unchecked {
                                    ++j;
                                }
                            }
                            // Withdraw from multiple vaults asynchronously(crosschain)
                            _liquidateSingleXChainMultiVault(
                                chainId,
                                superformIds,
                                amounts,
                                config.controller,
                                config.sXmV,
                                totalDebtReduction,
                                _toDynamicUint256Array(cache.assetsPerVault[i], cache.lens[i])
                            );
                            break;
                        }
                    }
                }
            }
            // If its multichain
            else {
                // If its single vault
                if (!cache.isMultiVault) {
                    uint256 chainsLen;
                    for (uint256 i = 0; i < cache.lens.length; i++) {
                        if (cache.lens[i] > 0) chainsLen++;
                    }

                    uint8[][] memory ambIds = new uint8[][](chainsLen);
                    uint64[] memory dstChainIds = new uint64[](chainsLen);
                    SingleVaultSFData[] memory singleVaultDatas = new SingleVaultSFData[](chainsLen);
                    uint256 lastChainsIndex;

                    for (uint256 i = 0; i < N_CHAINS; i++) {
                        if (cache.lens[i] > 0) {
                            dstChainIds[lastChainsIndex] = DST_CHAINS[i];
                            ++lastChainsIndex;
                        }
                    }
                    uint256[] memory totalDebtReductions = new uint256[](chainsLen);
                    for (uint256 i = 0; i < N_CHAINS; i++) {
                        totalDebtReductions[i] = cache.assetsPerVault[i][0];
                        singleVaultDatas[i] = SingleVaultSFData({
                            superformId: cache.dstVaults[i][0],
                            amount: cache.sharesPerVault[i][0],
                            outputAmount: config.mXsV.outputAmounts[i],
                            maxSlippage: config.mXsV.maxSlippages[i],
                            liqRequest: config.mXsV.liqRequests[i],
                            permit2data: "",
                            hasDstSwap: config.mXsV.hasDstSwaps[i],
                            retain4626: false,
                            receiverAddress: config.controller,
                            receiverAddressSP: address(0),
                            extraFormData: ""
                        });
                        ambIds[i] = config.mXsV.ambIds[i];
                        vaults[cache.dstVaults[i][0]].totalDebt =
                            _sub0(vaults[cache.dstVaults[i][0]].totalDebt, cache.assetsPerVault[i][0]).toUint128();
                    }
                    _liquidateMultiDstSingleVault(
                        ambIds, dstChainIds, singleVaultDatas, config.mXsV.value, totalDebtReductions
                    );
                }
                // If its multi-vault
                else {
                    // Cache the number of chains we will withdraw from
                    uint256 chainsLen;
                    for (uint256 i = 0; i < cache.lens.length; i++) {
                        if (cache.lens[i] > 0) chainsLen++;
                    }
                    uint8[][] memory ambIds = new uint8[][](chainsLen);
                    // Cacche destination chains
                    uint64[] memory dstChainIds = new uint64[](chainsLen);
                    // Cache multivault calls for each chain
                    MultiVaultSFData[] memory multiVaultDatas = new MultiVaultSFData[](chainsLen);
                    uint256 lastChainsIndex;

                    for (uint256 i = 0; i < N_CHAINS; i++) {
                        if (cache.lens[i] > 0) {
                            dstChainIds[lastChainsIndex] = DST_CHAINS[i];
                            ++lastChainsIndex;
                        }
                    }
                    uint256[] memory totalDebtReductions = new uint256[](chainsLen);
                    uint256[][] memory debtReductionsPerVault = new uint256[][](chainsLen);
                    for (uint256 i = 0; i < N_CHAINS; i++) {
                        bool[] memory emptyBoolArray = _getEmptyBoolArray(cache.lens[i]);
                        uint256[] memory superformIds = _toDynamicUint256Array(cache.dstVaults[i], cache.lens[i]);
                        multiVaultDatas[i] = MultiVaultSFData({
                            superformIds: superformIds,
                            amounts: _toDynamicUint256Array(cache.sharesPerVault[i], cache.lens[i]),
                            outputAmounts: config.mXmV.outputAmounts[i],
                            maxSlippages: config.mXmV.maxSlippages[i],
                            liqRequests: config.mXmV.liqRequests[i],
                            permit2data: "",
                            hasDstSwaps: config.mXmV.hasDstSwaps[i],
                            retain4626s: emptyBoolArray,
                            receiverAddress: config.controller,
                            receiverAddressSP: address(0),
                            extraFormData: ""
                        });
                        ambIds[i] = config.mXmV.ambIds[i];
                        debtReductionsPerVault[i] = _toDynamicUint256Array(cache.sharesPerVault[i], cache.lens[i]);
                        for (uint256 j = 0; j < superformIds.length;) {
                            vaults[superformIds[j]].totalDebt =
                                _sub0(vaults[superformIds[j]].totalDebt, cache.assetsPerVault[i][j]).toUint128();
                            totalDebtReductions[i] += cache.assetsPerVault[i][j];
                            unchecked {
                                ++j;
                            }
                        }
                    }
                    // Withdraw from multiple vaults and chains asynchronously
                    _liquidateMultiDstMultiVault(
                        ambIds,
                        dstChainIds,
                        multiVaultDatas,
                        config.mXmV.value,
                        totalDebtReductions,
                        debtReductionsPerVault
                    );
                }
            }
        }

        // Optimistically deduct all assets to withdraw from the total
        _totalIdle = cache.totalIdle.toUint128();
        _totalIdle -= cache.totalClaimableWithdraw.toUint128();
        _totalDebt = cache.totalDebt.toUint128();

        emit ProcessRedeemRequest(config.controller, config.shares);
        // Burn all shares from this contract(they already have been transferred)
        _burn(address(this), config.shares);
        // Fulfill request with instant withdrawals only
        _fulfillRedeemRequest(cache.sharesFulfilled, cache.totalClaimableWithdraw, config.controller);
    }

    /// @dev Withdraws assets from a single vault on the same chain
    /// @param vault Address of the vault to withdraw from
    /// @param amount Amount of shares to redeem
    /// @param minAmountOut Minimum amount of assets expected to receive
    /// @param receiver Address to receive the withdrawn assets
    /// @return withdrawn Amount of assets actually withdrawn
    function _liquidateSingleDirectSingleVault(
        address vault,
        uint256 amount,
        uint256 minAmountOut,
        address receiver
    )
        private
        returns (uint256 withdrawn)
    {
        uint256 balanceBefore = asset().balanceOf(address(this));
        ERC4626(vault).redeem(amount, address(this), receiver);
        withdrawn = asset().balanceOf(address(this)) - balanceBefore;
        if (withdrawn < minAmountOut) {
            revert InsufficientAssets();
        }
    }

    /// @dev Withdraws assets from multiple vaults on the same chain
    /// @param vaults_ Array of vault addresses to withdraw from
    /// @param amounts Array of share amounts to redeem from each vault
    /// @param minAmountsOut Array of minimum amounts of assets expected from each vault
    /// @param receiver Address to receive the withdrawn assets
    /// @return withdrawn Total amount of assets withdrawn from all vaults
    function _liquidateSingleDirectMultiVault(
        address[] memory vaults_,
        uint256[] memory amounts,
        uint256[] memory minAmountsOut,
        address receiver
    )
        private
        returns (uint256 withdrawn)
    {
        for (uint256 i = 0; i < vaults_.length; ++i) {
            withdrawn += _liquidateSingleDirectSingleVault(vaults_[i], amounts[i], minAmountsOut[i], receiver);
        }
    }

    /// @dev Initiates a withdrawal from a single vault on a different chain
    /// @param chainId ID of the destination chain
    /// @param superformId ID of the superform to withdraw from
    /// @param amount Amount of shares to withdraw
    /// @param receiver Address to receive the withdrawn assets
    /// @param config Configuration for the cross-chain withdrawal
    function _liquidateSingleXChainSingleVault(
        uint64 chainId,
        uint256 superformId,
        uint256 amount,
        address receiver,
        SingleXChainSingleVaultWithdraw memory config,
        uint256 totalDebtReduction
    )
        private
    {
        gateway.liquidateSingleXChainSingleVault{ value: config.value }(
            chainId, superformId, amount, receiver, config, totalDebtReduction
        );
    }

    /// @dev Initiates withdrawals from multiple vaults on a single different chain
    /// @param chainId ID of the destination chain
    /// @param superformIds Array of superform IDs to withdraw from
    /// @param amounts Array of share amounts to withdraw from each superform
    /// @param receiver Address to receive the withdrawn assets
    /// @param config Configuration for the cross-chain withdrawals
    function _liquidateSingleXChainMultiVault(
        uint64 chainId,
        uint256[] memory superformIds,
        uint256[] memory amounts,
        address receiver,
        SingleXChainMultiVaultWithdraw memory config,
        uint256 totalDebtReduction,
        uint256[] memory debtReductionPerVault
    )
        private
    {
        gateway.liquidateSingleXChainMultiVault{ value: config.value }(
            chainId, superformIds, amounts, receiver, config, totalDebtReduction, debtReductionPerVault
        );
    }

    /// @dev Initiates withdrawals from a single vault on multiple different chains
    /// @param ambIds Array of AMB (Asset Management Bridge) IDs for each chain
    /// @param dstChainIds Array of destination chain IDs
    /// @param singleVaultDatas Array of SingleVaultSFData structures for each withdrawal
    /// @param value Amount of native tokens to send with the transaction
    function _liquidateMultiDstSingleVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        SingleVaultSFData[] memory singleVaultDatas,
        uint256 value,
        uint256[] memory totalDebtReductions
    )
        private
    {
        gateway.liquidateMultiDstSingleVault{ value: value }(
            ambIds, dstChainIds, singleVaultDatas, totalDebtReductions, totalDebtReductions
        );
    }

    /// @dev Initiates withdrawals from multiple vaults on multiple different chains
    /// @param ambIds Array of AMB (Asset Management Bridge) IDs for each chain
    /// @param dstChainIds Array of destination chain IDs
    /// @param multiVaultDatas Array of MultiVaultSFData structures for each chain's withdrawals
    /// @param value Amount of native tokens to send with the transaction
    function _liquidateMultiDstMultiVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        MultiVaultSFData[] memory multiVaultDatas,
        uint256 value,
        uint256[] memory totalDebtReduction,
        uint256[][] memory debtReductionsPerVault
    )
        private
    {
        gateway.liquidateMultiDstMultiVault{ value: value }(
            ambIds, dstChainIds, multiVaultDatas, totalDebtReduction, debtReductionsPerVault
        );
    }

    function selectors() public pure returns (bytes4[] memory) {
        bytes4[] memory s = new bytes4[](3);
        s[0] = this.processRedeemRequest.selector;
        s[1] = this.previewWithdrawalRoute.selector;
        s[2] = this.fulfillSettledRequest.selector;
        return s;
    }
}
