// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import { ERC7540EngineBase } from "./common/ERC7540EngineBase.sol";

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

/// @title ERC7540EngineSignatures
/// @notice Implementation of a ERC4626 multi-vault deposit liquidity engine with cross-chain functionalities
/// @dev Extends ERC7540EngineBase contract and implements advanced redeem request processing
contract ERC7540EngineSignatures is ERC7540EngineBase {
    /// @notice Thrown when attempting to withdraw more assets than are currently available
    error InsufficientAvailableAssets();

    /// @notice Thrown when signature has expired
    error SignatureExpired();

    /// @notice Thrown when signature verification fails
    error InvalidSignature();

    /// @notice Thrown when nonce is invalid
    error InvalidNonce();

    /// @notice Thrown when there are not enough assets to fulfill a request
    error InsufficientAssets();

    /// @dev Emitted when a redeem request is processed
    event ProcessRedeemRequest(address indexed controller, uint256 shares);

    /// @notice Thrown when shares requested are greater than pending redeem request
    error ExcessiveSharesRequested();

    /// @notice Thrown when shares are already being processed crosschain
    error SharesInProcess();

    /// @notice Thrown when assets were not liquidated
    error AssetsNotLiquidated();

    /// @dev Safe casting operations for uint
    using SafeCastLib for uint256;

    /// @dev Safe transfer operations for ERC20 tokens
    using SafeTransferLib for address;

    /// @dev Library for vault-related operations
    using VaultLib for VaultData;

    /// @notice Verifies that a signature is valid for the given request parameters
    /// @param params The request parameters to verify
    /// @param deadline The timestamp after which the signature is no longer valid
    /// @param nonce The user's current nonce
    /// @param v The recovery byte of the signature
    /// @param r The r value of the signature
    /// @param s The s value of the signature
    function verifySignature(
        ProcessRedeemRequestParams calldata params,
        uint256 deadline,
        uint256 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        public
        view
        returns (bool)
    {
        // Check deadline
        if (block.timestamp > deadline) {
            revert SignatureExpired();
        }

        // Check nonce
        if (nonce != nonces(params.controller)) {
            revert InvalidNonce();
        }

        // Hash the parameters including deadline and nonce
        bytes32 paramsHash = computeHash(params, deadline, nonce);

        // Verify signature using SignatureCheckerLib
        return SignatureCheckerLib.isValidSignatureNow(signerRelayer, paramsHash, abi.encodePacked(r, s, v));
    }

    /// @notice Computes the hash of the request parameters
    /// @param params The request parameters
    /// @param deadline The timestamp after which the signature is no longer valid
    /// @param nonce The user's current nonce
    /// @return The computed hash
    function computeHash(
        ProcessRedeemRequestParams calldata params,
        uint256 deadline,
        uint256 nonce
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                params.controller, params.shares, params.sXsV, params.sXmV, params.mXsV, params.mXmV, deadline, nonce
            )
        );
    }

    /// @notice Process a request with a valid relayer signature
    /// @param params The request parameters
    /// @param deadline The timestamp after which the signature is no longer valid
    /// @param v The recovery byte of the signature
    /// @param r The r value of the signature
    /// @param s The s value of the signature
    function processSignedRequest(
        ProcessRedeemRequestParams calldata params,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
    {
        address controller = params.controller;
        // Get and increment nonce
        uint256 nonce = nonces(controller);

        // Verify signature
        if (!verifySignature(params, deadline, nonce, v, r, s)) {
            revert InvalidSignature();
        }

        /// @solidity memory-safe-assembly
        assembly {
            // Compute the nonce slot and load its value
            mstore(0x0c, _NONCES_SLOT_SEED)
            mstore(0x00, controller)
            let nonceSlot := keccak256(0x0c, 0x20)
            let nonceValue := sload(nonceSlot)
            // Increment and store the updated nonce
            sstore(nonceSlot, add(nonceValue, 1))
        }
        // Process the request
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
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       PRIVATE FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

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
    // Original function - modified to call helper functions
    function _processRedeemRequest(ProcessRedeemRequestConfig memory config) private {
        // Use struct to avoid stack too deep
        ProcessRedeemRequestCache memory cache;
        cache.totalIdle = _totalIdle;
        cache.totalDebt = _totalDebt;
        config.shares = Math.min(balanceOf(address(this)), config.shares);

        // Custom error check for shares greater than pending redeem request
        uint256 pendingShares = pendingRedeemRequest(config.controller);
        if (config.shares > pendingShares) revert ExcessiveSharesRequested();
        if (config.shares > pendingShares - pendingProcessedShares[config.controller]) revert SharesInProcess();

        cache.assets = convertToAssets(config.shares);
        cache.totalAssets = totalAssets();

        // Cannot process more assets than the
        if (cache.assets > totalWithdrawableAssets()) {
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

            _prepareWithdrawalRoute(cache, false);

            // Handle this chain withdrawals
            _processThisChainWithdrawals(config, cache);

            // Handle external chain withdrawals
            if (cache.isSingleChain) {
                _processSingleChainWithdrawals(config, cache);
            }

            if (cache.isMultiChain) {
                if (!cache.isMultiVault) {
                    _processMultiChainSingleVault(config, cache);
                } else {
                    _processMultiChainMultiVault(config, cache);
                }
            }
        }

        // Optimistically deduct all assets to withdraw from the total
        _totalIdle = cache.totalIdle.toUint128();
        _totalIdle -= cache.totalClaimableWithdraw.toUint128();
        _totalDebt = cache.totalDebt.toUint128();

        // Check that totalAssets was actually reduced by the amount to withdraw
        if (totalAssets() > cache.totalAssets - cache.amountToWithdraw) {
            revert AssetsNotLiquidated();
        }

        emit ProcessRedeemRequest(config.controller, config.shares);

        pendingProcessedShares[config.controller] += config.shares - cache.sharesFulfilled;

        // Burn all shares from this contract(they already have been transferred)
        _burn(address(this), config.shares);
        // Fulfill request with instant withdrawals only
        _fulfillRedeemRequest(cache.sharesFulfilled, cache.totalClaimableWithdraw, config.controller, true);
    }

    // New helper function for this chain withdrawals
    function _processThisChainWithdrawals(
        ProcessRedeemRequestConfig memory config,
        ProcessRedeemRequestCache memory cache
    )
        private
    {
        uint256 chainIndex = chainIndexes[THIS_CHAIN_ID];
        if (cache.lens[chainIndex] == 0) return;

        if (cache.lens[chainIndex] == 1) {
            // Process single vault
            uint256 sharesAmount = cache.sharesPerVault[chainIndex][0];
            uint256 assetsAmount = cache.assetsPerVault[chainIndex][0];
            uint256 superformId = cache.dstVaults[chainIndex][0];

            uint256 withdrawn =
                _liquidateSingleDirectSingleVault(vaults[superformId].vaultAddress, sharesAmount, 0, address(this));

            cache.sharesFulfilled += _convertToShares(assetsAmount, cache.totalAssets);
            _reduceVaultDebt(superformId, assetsAmount);
            cache.totalClaimableWithdraw += withdrawn;
            cache.totalIdle += withdrawn;
        } else {
            // Process multi vault
            uint256 len = cache.lens[chainIndex];
            address[] memory vaultAddresses = new address[](len);
            uint256[] memory amounts = new uint256[](len);
            uint256 requestedAssets;

            for (uint256 i = 0; i < len;) {
                vaultAddresses[i] = vaults[cache.dstVaults[chainIndex][i]].vaultAddress;
                amounts[i] = cache.sharesPerVault[chainIndex][i];
                uint256 superformId = cache.dstVaults[chainIndex][i];
                requestedAssets += cache.assetsPerVault[chainIndex][i];
                _reduceVaultDebt(superformId, cache.assetsPerVault[chainIndex][i]);
                unchecked {
                    ++i;
                }
            }

            uint256 withdrawn = _liquidateSingleDirectMultiVault(
                vaultAddresses, amounts, _getEmptyuintArray(amounts.length), address(this)
            );

            cache.totalClaimableWithdraw += withdrawn;
            cache.sharesFulfilled += _convertToShares(requestedAssets, cache.totalAssets);
            cache.totalIdle += withdrawn;
        }
    }

    // New helper function for single chain withdrawals
    function _processSingleChainWithdrawals(
        ProcessRedeemRequestConfig memory config,
        ProcessRedeemRequestCache memory cache
    )
        private
    {
        if (!cache.isMultiVault) {
            // Single chain, single vault
            uint256 superformId;
            uint256 amount;
            uint64 chainId;

            for (uint256 i = 0; i < N_CHAINS;) {
                if (DST_CHAINS[i] == THIS_CHAIN_ID) {
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                if (cache.lens[i] > 0) {
                    chainId = DST_CHAINS[i];
                    uint256 chainIndex = chainIndexes[chainId];
                    superformId = cache.dstVaults[i][0];
                    amount = cache.sharesPerVault[i][0];

                    _liquidateSingleXChainSingleVault(
                        chainId, superformId, amount, config.controller, config.sXsV, cache.assetsPerVault[i][0]
                    );

                    _reduceVaultDebt(superformId, cache.assetsPerVault[chainIndex][0]);
                    break;
                }
                unchecked {
                    ++i;
                }
            }
        } else {
            // Single chain, multi vault
            uint256[] memory superformIds;
            uint256[] memory amounts;
            uint64 chainId;

            for (uint256 i = 0; i < N_CHAINS;) {
                if (DST_CHAINS[i] == THIS_CHAIN_ID) {
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                if (cache.lens[i] > 0) {
                    chainId = DST_CHAINS[i];
                    superformIds = _toDynamicUint256Array(cache.dstVaults[i], cache.lens[i]);
                    amounts = _toDynamicUint256Array(cache.sharesPerVault[i], cache.lens[i]);
                    uint256 totalDebtReduction;

                    for (uint256 j = 0; j < superformIds.length;) {
                        _reduceVaultDebt(superformIds[j], cache.assetsPerVault[i][j]);
                        totalDebtReduction += cache.assetsPerVault[i][j];
                        unchecked {
                            ++j;
                        }
                    }

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
                unchecked {
                    ++i;
                }
            }
        }
    }

    // New helper function for multi chain withdrawals
    function _processMultiChainWithdrawals(
        ProcessRedeemRequestConfig memory config,
        ProcessRedeemRequestCache memory cache
    )
        private
    {
        if (!cache.isMultiVault) {
            _processMultiChainSingleVault(config, cache);
        } else {
            _processMultiChainMultiVault(config, cache);
        }
    }

    // New helper function specifically for multi-chain, single-vault scenario
    function _processMultiChainSingleVault(
        ProcessRedeemRequestConfig memory config,
        ProcessRedeemRequestCache memory cache
    )
        private
    {
        uint256 chainsLen;
        for (uint256 i = 0; i < cache.lens.length;) {
            if (cache.lens[i] > 0) chainsLen++;
            unchecked {
                ++i;
            }
        }

        uint8[][] memory ambIds = new uint8[][](chainsLen);
        uint64[] memory dstChainIds = new uint64[](chainsLen);
        SingleVaultSFData[] memory singleVaultDatas = new SingleVaultSFData[](chainsLen);
        uint256 lastChainsIndex;

        for (uint256 i = 0; i < N_CHAINS;) {
            if (cache.lens[i] > 0) {
                dstChainIds[lastChainsIndex] = DST_CHAINS[i];
                ++lastChainsIndex;
            }
            unchecked {
                ++i;
            }
        }

        uint256[] memory totalDebtReductions = new uint256[](chainsLen);

        for (uint256 i = 0; i < N_CHAINS;) {
            if (cache.lens[i] == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }

            totalDebtReductions[cache.lastIndex] = cache.assetsPerVault[i][0];
            singleVaultDatas[cache.lastIndex] = SingleVaultSFData({
                superformId: cache.dstVaults[i][0],
                amount: cache.sharesPerVault[i][0],
                outputAmount: config.mXsV.outputAmounts[cache.lastIndex],
                maxSlippage: config.mXsV.maxSlippages[cache.lastIndex],
                liqRequest: config.mXsV.liqRequests[cache.lastIndex],
                permit2data: "",
                hasDstSwap: config.mXsV.hasDstSwaps[cache.lastIndex],
                retain4626: false,
                receiverAddress: config.controller,
                receiverAddressSP: address(0),
                extraFormData: ""
            });

            ambIds[cache.lastIndex] = config.mXsV.ambIds[cache.lastIndex];
            _reduceVaultDebt(cache.dstVaults[i][0], cache.assetsPerVault[i][0]);
            cache.lastIndex++;
            unchecked {
                ++i;
            }
        }

        _liquidateMultiDstSingleVault(ambIds, dstChainIds, singleVaultDatas, config.mXsV.value, totalDebtReductions);
    }

    function _reduceVaultDebt(uint256 superformId, uint256 amount) private {
        unchecked {
            vaults[superformId].totalDebt =
                (amount >= vaults[superformId].totalDebt ? 0 : vaults[superformId].totalDebt - amount).toUint128();
        }
    }

    // New helper function specifically for multi-chain, multi-vault scenario
    function _processMultiChainMultiVault(
        ProcessRedeemRequestConfig memory config,
        ProcessRedeemRequestCache memory cache
    )
        private
    {
        uint256 chainsLen;
        for (uint256 i = 0; i < cache.lens.length;) {
            if (cache.lens[i] > 0) chainsLen++;
            unchecked {
                ++i;
            }
        }

        uint8[][] memory ambIds = new uint8[][](chainsLen);
        uint64[] memory dstChainIds = new uint64[](chainsLen);
        MultiVaultSFData[] memory multiVaultDatas = new MultiVaultSFData[](chainsLen);
        uint256 lastChainsIndex;

        for (uint256 i = 0; i < N_CHAINS;) {
            if (cache.lens[i] > 0) {
                dstChainIds[lastChainsIndex] = DST_CHAINS[i];
                ++lastChainsIndex;
            }
            unchecked {
                ++i;
            }
        }

        uint256[] memory totalDebtReductions = new uint256[](chainsLen);
        uint256[][] memory debtReductionsPerVault = new uint256[][](chainsLen);

        for (uint256 i = 0; i < N_CHAINS;) {
            if (cache.lens[i] == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }

            bool[] memory emptyBoolArray = _getEmptyBoolArray(cache.lens[i]);
            uint256[] memory superformIds = _toDynamicUint256Array(cache.dstVaults[i], cache.lens[i]);

            multiVaultDatas[cache.lastIndex] = MultiVaultSFData({
                superformIds: superformIds,
                amounts: _toDynamicUint256Array(cache.sharesPerVault[i], cache.lens[i]),
                outputAmounts: config.mXmV.outputAmounts[cache.lastIndex],
                maxSlippages: config.mXmV.maxSlippages[cache.lastIndex],
                liqRequests: config.mXmV.liqRequests[cache.lastIndex],
                permit2data: "",
                hasDstSwaps: config.mXmV.hasDstSwaps[cache.lastIndex],
                retain4626s: emptyBoolArray,
                receiverAddress: config.controller,
                receiverAddressSP: address(0),
                extraFormData: ""
            });

            ambIds[cache.lastIndex] = config.mXmV.ambIds[cache.lastIndex];
            debtReductionsPerVault[cache.lastIndex] = _toDynamicUint256Array(cache.sharesPerVault[i], cache.lens[i]);

            for (uint256 j = 0; j < superformIds.length;) {
                _reduceVaultDebt(superformIds[j], cache.assetsPerVault[i][j]);
                totalDebtReductions[cache.lastIndex] += cache.assetsPerVault[i][j];
                unchecked {
                    ++j;
                }
            }

            cache.lastIndex++;
            unchecked {
                ++i;
            }
        }

        _liquidateMultiDstMultiVault(
            ambIds, dstChainIds, multiVaultDatas, config.mXmV.value, totalDebtReductions, debtReductionsPerVault
        );
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
        for (uint256 i = 0; i < vaults_.length;) {
            withdrawn += _liquidateSingleDirectSingleVault(vaults_[i], amounts[i], minAmountsOut[i], receiver);

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Initiates a withdrawal from a single vault on a different chain
    /// @param chainId ID of the destination chain
    /// @param superformId ID of the superform to withdraw from
    /// @param amount Amount of shares to withdraw
    /// @param receiver Address to receive the withdrawn assets
    /// @param config Configuration for the cross-chain withdrawal
    /// @param totalDebtReduction total debt reductions per chain
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
    /// @param totalDebtReduction Total debt reduction for this chain's vaults
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
    /// @param totalDebtReductions Array of total debt reductions per destination chain
    function _liquidateMultiDstSingleVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        SingleVaultSFData[] memory singleVaultDatas,
        uint256 value,
        uint256[] memory totalDebtReductions
    )
        private
    {
        gateway.liquidateMultiDstSingleVault{ value: value }(ambIds, dstChainIds, singleVaultDatas, totalDebtReductions);
    }

    /// @dev Initiates withdrawals from multiple vaults on multiple different chains
    /// @param ambIds Array of AMB (Asset Management Bridge) IDs for each chain
    /// @param dstChainIds Array of destination chain IDs
    /// @param multiVaultDatas Array of MultiVaultSFData structures for each chain's withdrawals
    /// @param value Amount of native tokens to send with the transaction
    /// @param totalDebtReduction Array of total debt reductions per chain
    /// @param debtReductionsPerVault Array of arrays detailing debt reductions per vault per chain
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

    /// @dev Helper function to fetch module function selectors
    function selectors() public pure returns (bytes4[] memory) {
        bytes4[] memory s = new bytes4[](3);
        s[0] = this.processSignedRequest.selector;
        s[1] = this.verifySignature.selector;
        s[2] = this.computeHash.selector;
        return s;
    }
}
