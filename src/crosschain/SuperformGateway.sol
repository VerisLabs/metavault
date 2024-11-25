/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IBaseRouter, IMaxApyCrossChainVault, ISuperPositions } from "interfaces/Lib.sol";
import {
    Harvest,
    MultiDstMultiVaultStateReq,
    MultiDstSingleVaultStateReq,
    MultiVaultSFData,
    MultiXChainMultiVaultWithdraw,
    MultiXChainSingleVaultWithdraw,
    SingleDirectMultiVaultStateReq,
    SingleDirectSingleVaultStateReq,
    SingleVaultSFData,
    SingleXChainMultiVaultStateReq,
    SingleXChainMultiVaultWithdraw,
    SingleXChainSingleVaultStateReq,
    SingleXChainSingleVaultWithdraw,
    VaultData,
    VaultLib,
    VaultReport
} from "types/Lib.sol";
import { LibClone } from "solady/utils/LibClone.sol";


contract SuperformGateway {
    using VaultLib for VaultData;
    // Deploy and set the receiver implementation
    ERC20Receiver receiverImplementation;
    ISuperPositions private _superPositions;
    IBaseRouter private _vaultRouter;
    IMaxApyCrossChainVault public vault;
    /// @notice Cached value of total assets that are being bridged at the moment
    uint256 public totalpendingXChainInvests;
    /// @notice Cached value of total assets that are being bridged at the moment
    uint256 public totalPendingXChainWithdraws;
    /// @notice Cached value of total assets that are being bridged at the moment
    uint256 public totalPendingXChainDivests;
    /// @notice pending bridged assets for each vault
    mapping(uint256 superformId => uint256 amount) public pendingXChainInvests;
    /// @notice pending bridged assets for each vault
    mapping(uint256 superformId => uint256 amount) public pendingXChainWithdraws;
    // @notice pending bridged assets for each vault
    mapping(uint256 superformId => uint256 amount) public pendingXChainDivests;

    constructor(IMaxApyCrossChainVault _vault, IBaseRouter _vaultRouter_, ISuperPositions _superPositions_) {
        vault = _vault;
        _vaultRouter = _vaultRouter_;
        _superPositions = _superPositions_;
          // Deploy and set the receiver implementation
        receiverImplementation = address(new ERC20Receiver(config.asset));
    }

    modifier onlyVault() {
        if (msg.sender != vault) {
            revert();
        }
        _;
    }

    /// @notice Modifier to refund dust ether for crosschain transactions
    /// @dev Reverts if the msg.value was not enough
    modifier refundGas() {
        uint256 balanceBefore;
        assembly {
            balanceBefore := sub(selfbalance(), callvalue())
        }
        _;
        assembly {
            let balanceAfter := selfbalance()
            switch lt(balanceAfter, balanceBefore)
            case true {
                mstore(0x00, 0x1c26714c) // `InsufficientGas()`.
                revert(0x1c, 0x04)
            }
            case false {
                // Transfer all the ETH to sender and check if it succeeded or not.
                if iszero(call(gas(), origin(), balanceAfter, codesize(), 0x00, codesize(), 0x00)) {
                    mstore(0x00, 0xb12d13eb) // `ETHTransferFailed()`.
                    revert(0x1c, 0x04)
                }
            }
        }
    }

    function balanceOf(address account, uint256 superformId) external view returns (uint256) {
        return _superPositions.balanceOf(account, superformId);
    }

    /// @notice Invests assets from this vault into a single target vault on a different chain
    /// @dev Only callable by addresses with the MANAGER_ROLE
    /// @param req Crosschain deposit request
    function investSingleXChainSingleVault(SingleXChainSingleVaultStateReq calldata req)
        external
        payable
        onlyVault
        refundGas
    {
        uint256 superformId = req.superformData.superformId;

        // We cannot invest more till the previous investment is successfully completed
        if (pendingXChainInvests[superformId] != 0) revert XChainDepositsPending();

        VaultData memory vault = vault.vaults(superformId);
        if (!vault.isVaultListed(vault.vaultAddress)) revert VaultNotListed();

        // Initiate the cross-chain deposit via the vault router
        _vaultRouter.singleXChainSingleVaultDeposit{ value: msg.value }(req);

        // Account assets as pending
        pendingXChainInvests[superformId] = amount;
        totalpendingXChainInvests += amount;
    }

    /// @notice Placeholder for investing in multiple vaults across chains
    /// @param req Crosschain deposit request
    function investSingleXChainMultiVault(SingleXChainMultiVaultStateReq calldata req)
        external
        payable
        onlyVault
        refundGas
        returns (uint256 totalAmount)
    {
        for (uint256 i = 0; i < req.superformsData.superformIds.length; ++i) {
            uint256 superformId = req.superformsData.superformIds[i];

            // Cant invest in a vault that is not in the portfolio
            VaultData memory vault = vault.vaults(superformId);
            if (!vault.isVaultListed(vault.vaultAddress)) revert VaultNotListed();

            // We cannot invest more till the previous investment is successfully completed
            if (pendingXChainInvests[superformId] != 0) revert XChainDepositsPending();
            // Account assets as pending
            pendingXChainInvests[superformId] = req.superformsData.amounts[i];
        }
        _vaultRouter.singleXChainMultiVaultDeposit{ value: msg.value }(req);
        totalpendingXChainInvests += totalAmount;
    }

    /// @notice Placeholder for investing multiple assets in a single vault across chains
    /// @dev Not implemented yet
    function investMultiXChainSingleVault(MultiDstSingleVaultStateReq calldata req)
        external
        payable
        onlyVault
        refundGas
        returns (uint256 totalAmount)
    {
        for (uint256 i = 0; i < req.superformsData.length;) {
            uint256 superformId = req.superformsData[i].superformId;
            uint256 amount = req.superformsData[i].amount;

            // Cant invest in a vault that is not in the portfolio
            VaultData memory vault = vault.vaults(superformId);
            if (!vault.isVaultListed(vault.vaultAddress)) revert VaultNotListed();

            // We cannot invest more till the previous investment is successfully completed
            if (pendingXChainInvests[superformId] != 0) revert XChainDepositsPending();
            // Account assets as pending
            pendingXChainInvests[superformId] = amount;
            totalAmount += amount;
            unchecked {
                ++i;
            }
        }
        _vaultRouter.multiDstSingleVaultDeposit{ value: msg.value }(req);
        totalpendingXChainInvests += totalAmount;
    }

    /// @notice Placeholder for investing multiple assets in multiple vaults across chains
    /// @dev Not implemented yet
    function investMultiXChainMultiVault(MultiDstMultiVaultStateReq calldata req)
        external
        payable
        onlyVault
        refundGas
        returns (uint256 totalAmount)
    {
        for (uint256 i = 0; i < req.superformsData.length; i++) {
            uint256[] memory superformIds = req.superformsData[i].superformIds;
            uint256[] memory amounts = req.superformsData[i].amounts;
            for (uint256 j = 0; j < superformIds.length; j++) {
                uint256 superformId = superformIds[j];
                uint256 amount = amounts[j];

                // Cant invest in a vault that is not in the portfolio
                VaultData memory vault = vault.vaults(superformId);
                if (!vault.isVaultListed(vault.vaultAddress)) revert VaultNotListed();
                // We cannot invest more till the previous investment is successfully completed
                if (pendingXChainInvests[superformId] != 0) revert XChainDepositsPending();
                // Account assets as pending
                pendingXChainInvests[superformId] = amount;
                totalAmount += amount;
            }
        }
        _vaultRouter.multiDstMultiVaultDeposit{ value: msg.value }(req);
        totalpendingXChainInvests += totalAmount;
    }

    function divestSingleXChainSingleVault(SingleXChainSingleVaultStateReq calldata req)
        external
        payable
        onlyVault
        refundGas
        returns (uint256 sharesValue)
    {
        uint256 superformId = req.superformData.superformId;

        VaultData memory vault = vault.vaults(superformId);
        if (!vault.isVaultListed(vault.vaultAddress)) revert VaultNotListed();

        if (pendingXChainWithdraws[superformId] != 0) revert XChainWithdrawsPending();

        address receiver = receiver(
            address(uint160(uint256(keccak256(abi.encodePacked(address(this), req.superformData.superformId)))))
        );

        _vaultRouter.singleXChainSingleVaultWithdraw{ value: msg.value }(req);

        // Update the vault's internal accounting
        sharesValue = vault.convertToAssets(req.superformData.amount, true);
        uint128 amountUint128 = sharesValue.toUint128();

        // Account assets as pending
        pendingXChainDivests[superformId] = amountUint128;
        totalPendingXChainDivests += amountUint128;
    }

    function divestSingleXChainMultiVault(SingleXChainMultiVaultStateReq calldata req)
        external
        payable
        onlyVault
        refundGas
        returns (uint256 totalAmount)
    {
        for (uint256 i = 0; i < req.superformsData.superformIds.length; ++i) {
            uint256 superformId = req.superformsData.superformIds[i];
            // Cant invest in a vault that is not in the portfolio
            VaultData memory vault = vault.vaults(superformId);
            if (!vault.isVaultListed(vault.vaultAddress)) revert VaultNotListed();
            // We cannot invest more till the previous investment is successfully completed
            if (pendingXChainWithdraws[superformId] != 0) revert XChainWithdrawsPending();
            uint256 amount = vault.convertToAssets(req.superformsData.amounts[i], true);
            // Account assets as pending
            pendingXChainWithdraws[superformId] = amount;
            // Update the vault's internal accounting
            totalAmount += amount;
        }
        _vaultRouter.singleXChainMultiVaultWithdraw{ value: msg.value }(req);
        totalPendingXChainWithdraws += totalAmount;
    }

    function divestMultiXChainSingleVault(MultiDstSingleVaultStateReq calldata req)
        external
        payable
        onlyVault
        refundGas
    {
        uint256 totalAmount;
        for (uint256 i = 0; i < req.superformsData.length;) {
            uint256 superformId = req.superformsData[i].superformId;
            // Retrieve the vault data for the target vault
            VaultData memory vault = vault.vaults(superformId);
            // Cant invest in a vault that is not in the portfolio
            if (!vault.isVaultListed(vault.vaultAddress)) revert VaultNotListed();
            uint256 amount = vault.convertToAssets(req.superformsData[i].amount, true);

            // We cannot invest more till the previous investment is successfully completed
            if (pendingXChainWithdraws[superformId] != 0) revert XChainDepositsPending();
            // Account assets as pending
            pendingXChainWithdraws[superformId] = amount;
            totalAmount += amount;
            unchecked {
                ++i;
            }
        }
        _vaultRouter.multiDstSingleVaultDeposit{ value: msg.value }(req);
        totalPendingXChainWithdraws += totalAmount;
    }

    function divestMultiXChainMultiVault(MultiDstMultiVaultStateReq calldata req)
        external
        payable
        onlyVault
        refundGas
    {
        uint256 totalAmount;
        for (uint256 i = 0; i < req.superformsData.length; i++) {
            uint256[] memory superformIds = req.superformsData[i].superformIds;
            uint256[] memory amounts = req.superformsData[i].amounts;
            for (uint256 j = 0; j < superformIds.length; j++) {
                uint256 superformId = superformIds[j];
                // Cant invest in a vault that is not in the portfolio
                VaultData memory vault = vault.vaults(superformId);
                if (!vault.isVaultListed(vault.vaultAddress)) revert VaultNotListed();

                uint256 amount = vault.convertToAssets(amounts[j], true);
                // Account assets as pending
                pendingXChainWithdraws[superformId] = amount;

                // We cannot invest more till the previous investment is successfully completed
                if (pendingXChainWithdraws[superformId] != 0) revert XChainDepositsPending();
                totalAmount += amount;
            }
        }
        _vaultRouter.multiDstMultiVaultDeposit{ value: msg.value }(req);
        totalPendingXChainWithdraws += totalAmount;
    }

     /// @dev Initiates a withdrawal from a single vault on a different chain
    /// @param chainId ID of the destination chain
    /// @param superformId ID of the superform to withdraw from
    /// @param amount Amount of shares to withdraw
    /// @param receiver Address to receive the withdrawn assets
    /// @param config Configuration for the cross-chain withdrawal
    function liquidateSingleXChainSingleVault(
        uint64 chainId,
        uint256 superformId,
        uint256 amount,
        address receiver,
        SingleXChainSingleVaultWithdraw memory config
    )
        private
    {
        SingleXChainSingleVaultStateReq memory params = SingleXChainSingleVaultStateReq({
            ambIds: config.ambIds,
            dstChainId: chainId,
            superformData: SingleVaultSFData({
                superformId: superformId,
                amount: amount,
                outputAmount: config.outputAmount,
                maxSlippage: config.maxSlippage,
                liqRequest: config.liqRequest,
                permit2data: _getEmptyBytes(),
                hasDstSwap: config.hasDstSwap,
                retain4626: false,
                receiverAddress: receiver,
                receiverAddressSP: address(0),
                extraFormData: _getEmptyBytes()
            })
        });
        _vaultRouter.singleXChainSingleVaultWithdraw{ value: config.value }(params);
    }

    /// @dev Initiates withdrawals from multiple vaults on a single different chain
    /// @param chainId ID of the destination chain
    /// @param superformIds Array of superform IDs to withdraw from
    /// @param amounts Array of share amounts to withdraw from each superform
    /// @param receiver Address to receive the withdrawn assets
    /// @param config Configuration for the cross-chain withdrawals
    function liquidateSingleXChainMultiVault(
        uint64 chainId,
        uint256[] memory superformIds,
        uint256[] memory amounts,
        address receiver,
        SingleXChainMultiVaultWithdraw memory config
    )
        private
    {
        uint256 len = superformIds.length;
        SingleXChainMultiVaultStateReq memory params = SingleXChainMultiVaultStateReq({
            ambIds: config.ambIds,
            dstChainId: chainId,
            superformsData: MultiVaultSFData({
                superformIds: superformIds,
                amounts: amounts,
                outputAmounts: config.outputAmounts,
                maxSlippages: config.maxSlippages,
                liqRequests: config.liqRequests,
                permit2data: _getEmptyBytes(),
                hasDstSwaps: config.hasDstSwaps,
                retain4626s: _getEmptyBoolArray(len),
                receiverAddress: receiver,
                receiverAddressSP: address(0),
                extraFormData: _getEmptyBytes()
            })
        });
        _vaultRouter.singleXChainMultiVaultWithdraw{ value: config.value }(params);
    }

    /// @dev Initiates withdrawals from a single vault on multiple different chains
    /// @param ambIds Array of AMB (Asset Management Bridge) IDs for each chain
    /// @param dstChainIds Array of destination chain IDs
    /// @param singleVaultDatas Array of SingleVaultSFData structures for each withdrawal
    /// @param value Amount of native tokens to send with the transaction
    function liquidateMultiDstSingleVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        SingleVaultSFData[] memory singleVaultDatas,
        uint256 value
    )
        internal
    {
        MultiDstSingleVaultStateReq memory params =
            MultiDstSingleVaultStateReq({ ambIds: ambIds, dstChainIds: dstChainIds, superformsData: singleVaultDatas });
        _vaultRouter.multiDstSingleVaultWithdraw{ value: value }(params);
    }

    /// @dev Initiates withdrawals from multiple vaults on multiple different chains
    /// @param ambIds Array of AMB (Asset Management Bridge) IDs for each chain
    /// @param dstChainIds Array of destination chain IDs
    /// @param multiVaultDatas Array of MultiVaultSFData structures for each chain's withdrawals
    /// @param value Amount of native tokens to send with the transaction
    function liquidateMultiDstMultiVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        MultiVaultSFData[] memory multiVaultDatas,
        uint256 value
    )
        private
    {
        MultiDstMultiVaultStateReq memory params =
            MultiDstMultiVaultStateReq({ ambIds: ambIds, dstChainIds: dstChainIds, superformsData: multiVaultDatas });
        _vaultRouter.multiDstMultiVaultWithdraw{ value: value }(params);
    }

    /// @dev Supports ERC1155 interface detection
    /// @param interfaceId The interface identifier, as specified in ERC-165
    /// @return isSupported True if the contract supports the interface, false otherwise
    function supportsInterface(bytes4 interfaceId) public pure returns (bool isSupported) {
        if (interfaceId == 0x4e2312e0) return true;
    }

    /// @notice Handles the receipt of a single ERC1155 token type
    /// @dev This function is called at the end of a `safeTransferFrom` after the balance has been updated
    /// @param operator The address which initiated the transfer (i.e. msg.sender)
    /// @param from The address which previously owned the token
    /// @param superformId The ID of the token being transferred
    /// @param value The amount of tokens being transferred
    /// @param data Additional data with no specified format
    /// @return bytes4 `bytes4(keccak256("onERC1155Received(address,address,uint,uint,bytes)"))`
    function onERC1155Received(
        address operator,
        address from,
        uint256 superformId,
        uint256 value,
        bytes memory data
    )
        public
        returns (bytes4)
    {
        // Silence compiler warnings
        operator;
        from;
        value;
        data;
        uint256 bridgedAssets = pendingXChainInvests[superformId];
        delete pendingXChainInvests[superformId];
        totalpendingXChainInvests -= bridgedAssets;
        _superPositions.safeTransferFrom(address(this), address(vault), superformId, value);
        vault.settleXChainInvest(superformId, bridgetAssets);
        return this.onERC1155Received.selector;
    }

    /// @notice Handles the receipt of multiple ERC1155 token types
    /// @dev This function is called at the end of a `safeBatchTransferFrom` after the balances have been updated
    /// @param operator The address which initiated the batch transfer (i.e. msg.sender)
    /// @param from The address which previously owned the tokens
    /// @param superformIds An array containing ids of each token being transferred (order and length must match values
    /// array)
    /// @param values An array containing amounts of each token being transferred (order and length must match ids
    /// array)
    /// @param data Additional data with no specified format
    /// @return bytes4 `bytes4(keccak256("onERC1155BatchReceived(address,address,uint[],uint[],bytes)"))`
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] memory superformIds,
        uint256[] memory values,
        bytes memory data
    )
        public
        returns (bytes4)
    {
        // Silence compiler warnings
        operator;
        from;
        values;
        data;
        for (uint256 i = 0; i < superformIds.length; ++i) {
            onERC1155Received(address(0), address(0), superformIds[i], 0, "");
        }
        return this.onERC1155BatchReceived.selector;
    }

    /// @dev Returns the delegatee of a owner to receive the assets
    /// @dev If it doesnt exist it deploys it at the moment
    /// @notice receiverAddress returns delegatee
    function receiver(address controller) public returns (address receiverAddress) {
        address current = receivers[controller];
        if (current != address(0)) {
            return current;
        } else {
            receiverAddress =
                LibClone.clone(receiverImplementation, abi.encodeWithSignature("initialize(address)", controller));
            receivers[controller] = receiverAddress;
        }
    }


    /// @notice fulfills the already settled redeem requests
    /// @param controller controller address
    function _fulfillSettledRequests(address controller) private {
        ERC20Receiver receiverContract = ERC20Receiver(receiver(controller));
        uint256 claimableXChain = receiverContract.balance();
        receiverContract.pull(claimableXChain);
        uint256 shares = pendingRedeemRequest(controller);
        _fulfillRedeemRequest(shares, claimableXChain, controller);
        emit FulfillRedeemRequest(controller, shares, claimableXChain);
    }
}
