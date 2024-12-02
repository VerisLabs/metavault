/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ERC20Receiver } from "./ERC20Receiver.sol";
import { IBaseRouter, IMetaVault, ISuperPositions } from "interfaces/Lib.sol";

import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { Initializable } from "solady/utils/Initializable.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
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

/// @title SuperformGateway
/// @author Unlockd
/// @notice Gateway contract that handles cross-chain communication between MetaVault and Superform protocol
/// @dev Manages deposits and withdrawals across different chains through Superform's infrastructure
contract SuperformGateway is Initializable, OwnableRoles {
    using VaultLib for VaultData;
    using SafeTransferLib for address;

    /// @notice Thrown when there are pending cross-chain deposits
    error XChainDepositsPending();
    /// @notice Thrown when there are pending cross-chain withdrawals
    error XChainWithdrawsPending();
    /// @notice Thrown when attempting to interact with an unlisted vault
    error VaultNotListed();

    /// @notice Emitted when a cross-chain liquidation is initiated
    /// @param controller The address initiating the liquidation
    /// @param superformIds Array of Superform IDs involved
    /// @param requestedAssets Total amount of assets requested
    /// @param key Unique identifier for the liquidation assets receiver contract
    event LiquidateXChain(
        address indexed controller, uint256[] indexed superformIds, uint256 indexed requestedAssets, bytes key
    );

    /// @notice Emitted when a cross-chain divestment is initiated
    /// @param superformIds Array of Superform IDs being divested
    /// @param requestedAssets Total amount of assets requested
    /// @param key Unique identifier for the divest assets receiver contract
    event DivestXChain(uint256[] indexed superformIds, uint256 indexed requestedAssets, bytes key);

    /// @notice Role identifier for admin privileges
    uint256 public constant ADMIN_ROLE = _ROLE_0;
    /// @notice Role identifier for relayer
    uint256 public constant RELAYER_ROLE = _ROLE_0;
    /// @notice ERC20Receiver contract implementation to clone
    address public receiverImplementation;
    /// @notice Superpositions
    ISuperPositions public superPositions;
    /// @notice Superform router
    IBaseRouter public superformRouter;
    /// @notice underlying vault
    IMetaVault public vault;
    /// @notice asset of underying vault
    address public asset;
    /// @notice Receiver delegation for withdrawals
    mapping(address => mapping(bytes => address)) public receivers;
    /// @notice Assets requested in each liquidation
    mapping(address => mapping(bytes => uint256)) public requestedAssets;
    /// @notice Cached value of total assets that are being bridged at the moment
    uint256 public totalpendingXChainInvests;
    /// @notice Cached value of total assets per id that are being bridged at the moment
    mapping(uint256 => uint256) public pendingXChainInvests;
    /// @notice Cached value of total assets that are being bridged at the moment
    uint256 public totalPendingXChainDivests;
    /// @notice Gap for upgradeability
    uint256[20] private __gap;

    constructor() { }

    /// @notice Initializes the gateway contract
    /// @param _vault Address of the MetaVault contract
    /// @param _owner Address that will own the contract
    /// @param _superformRouter Address of Superform's router contract
    /// @param _superPositions Address of Superform's ERC1155 contract
    function initialize(
        IMetaVault _vault,
        address _owner,
        IBaseRouter _superformRouter,
        ISuperPositions _superPositions
    )
        external
        initializer
    {
        vault = _vault;
        asset = vault.asset();
        superformRouter = _superformRouter;
        superPositions = _superPositions;
        // Deploy and set the receiver implementation
        receiverImplementation = address(new ERC20Receiver(asset));
        asset.safeApprove(address(superformRouter), type(uint256).max);
        superPositions.setApprovalForAll(address(superformRouter), true);
        _initializeOwner(_owner);
    }

    /// @notice Modifier that restricts function access to the vault contract
    modifier onlyVault() {
        if (msg.sender != address(vault)) {
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

    /// @notice Gets the balance of a specific Superform ID for an account
    /// @param account The address to check the balance for
    /// @param superformId The ID of the Superform position
    /// @return The balance of the specified Superform ID
    function balanceOf(address account, uint256 superformId) external view returns (uint256) {
        return superPositions.balanceOf(account, superformId);
    }

    /// @notice Invests assets from this vault into a single target vault on a different chain
    /// @dev Only callable by addresses with the MANAGER_ROLE
    /// @param req Crosschain deposit request
    function investSingleXChainSingleVault(SingleXChainSingleVaultStateReq memory req)
        external
        payable
        onlyVault
        refundGas
    {
        uint256 superformId = req.superformData.superformId;

        VaultData memory vaultObj = vault.getVault(superformId);

        if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();

        uint256 amount = req.superformData.amount;

        asset.safeTransferFrom(address(vault), address(this), amount);

        req.superformData.receiverAddressSP = address(this);
        // Initiate the cross-chain deposit via the vault router
        superformRouter.singleXChainSingleVaultDeposit{ value: msg.value }(req);

        pendingXChainInvests[superformId] += amount;
        totalpendingXChainInvests = amount;
    }

    /// @notice Placeholder for investing in multiple vaults across chains
    /// @param req Crosschain deposit request
    function investSingleXChainMultiVault(SingleXChainMultiVaultStateReq memory req)
        external
        payable
        onlyVault
        refundGas
        returns (uint256 totalAmount)
    {
        req.superformsData.receiverAddressSP = address(this);
        for (uint256 i = 0; i < req.superformsData.superformIds.length; ++i) {
            uint256 superformId = req.superformsData.superformIds[i];

            uint256 amount = req.superformsData.amounts[i];

            pendingXChainInvests[superformId] = amount;

            totalAmount += amount;

            // Cant invest in a vault that is not in the portfolio
            VaultData memory vaultObj = vault.getVault(superformId);
            if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();
        }
        totalpendingXChainInvests += totalAmount;
        asset.safeTransferFrom(address(vault), address(this), totalAmount);
        superformRouter.singleXChainMultiVaultDeposit{ value: msg.value }(req);
    }

    /// @notice Placeholder for investing multiple assets in a single vault across chains
    /// @dev Not implemented yet
    function investMultiXChainSingleVault(MultiDstSingleVaultStateReq memory req)
        external
        payable
        onlyVault
        refundGas
        returns (uint256 totalAmount)
    {
        for (uint256 i = 0; i < req.superformsData.length;) {
            uint256 superformId = req.superformsData[i].superformId;
            uint256 amount = req.superformsData[i].amount;

            req.superformsData[i].receiverAddressSP = address(this);

            // Cant invest in a vault that is not in the portfolio
            VaultData memory vaultObj = vault.getVault(superformId);
            if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();

            pendingXChainInvests[superformId] = amount;
            totalAmount += amount;
            unchecked {
                ++i;
            }
        }
        asset.safeTransferFrom(address(vault), address(this), totalAmount);
        superformRouter.multiDstSingleVaultDeposit{ value: msg.value }(req);
        totalpendingXChainInvests += totalAmount;
    }

    /// @notice Placeholder for investing multiple assets in multiple vaults across chains
    /// @dev Not implemented yet
    function investMultiXChainMultiVault(MultiDstMultiVaultStateReq memory req)
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

                req.superformsData[i].receiverAddressSP = address(this);

                // Cant invest in a vault that is not in the portfolio
                VaultData memory vaultObj = vault.getVault(superformId);
                if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();

                pendingXChainInvests[superformId] = amount;
                totalAmount += amount;
            }
        }
        totalpendingXChainInvests += totalAmount;
        asset.safeTransferFrom(address(vault), address(this), totalAmount);
        superformRouter.multiDstMultiVaultDeposit{ value: msg.value }(req);
    }

    /// @notice Divests assets from a single vault on a different chain
    /// @dev Transfers Superform NFTs from vault to this contract and initiates withdrawal
    /// @param req The cross-chain withdrawal request parameters
    /// @return sharesValue The value of shares being withdrawn in terms of underlying assets
    function divestSingleXChainSingleVault(SingleXChainSingleVaultStateReq memory req)
        external
        payable
        onlyVault
        refundGas
        returns (uint256 sharesValue)
    {
        uint256 superformId = req.superformData.superformId;

        bytes memory key = abi.encode(superformId);

        address receiver = getReceiver(address(this), key);

        VaultData memory vaultObj = vault.getVault(superformId);
        if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();

        req.superformData.receiverAddress = receiver;

        // Update the vault's internal accounting
        sharesValue = vaultObj.convertToAssets(req.superformData.amount, true);

        totalPendingXChainDivests += sharesValue;

        superPositions.safeTransferFrom(address(vault), address(this), superformId, req.superformData.amount, "");

        superformRouter.singleXChainSingleVaultWithdraw{ value: msg.value }(req);

        uint256[] memory superformIds = new uint256[](1);
        superformIds[0] = superformId;

        emit DivestXChain(superformIds, sharesValue, key);
    }

    /// @notice Divests assets from multiple vaults on a single chain
    /// @dev Batch transfers Superform NFTs and initiates withdrawals for multiple vaults
    /// @param req The cross-chain multi-vault withdrawal request parameters
    /// @return totalAmount The total value of shares being withdrawn
    function divestSingleXChainMultiVault(SingleXChainMultiVaultStateReq memory req)
        external
        payable
        onlyVault
        refundGas
        returns (uint256 totalAmount)
    {
        for (uint256 i = 0; i < req.superformsData.superformIds.length; ++i) {
            uint256 superformId = req.superformsData.superformIds[i];

            // Cant invest in a vault that is not in the portfolio
            VaultData memory vaultObj = vault.getVault(superformId);
            if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();

            uint256 amount = vaultObj.convertToAssets(req.superformsData.amounts[i], true);

            // Update the vault's internal accounting
            totalAmount += amount;
        }

        bytes memory key = abi.encode(req.superformsData.superformIds);
        address receiver = getReceiver(address(this), key);
        req.superformsData.receiverAddress = receiver;

        superPositions.safeBatchTransferFrom(
            address(vault), address(this), req.superformsData.superformIds, req.superformsData.amounts, ""
        );
        superformRouter.singleXChainMultiVaultWithdraw{ value: msg.value }(req);
        totalPendingXChainDivests += totalAmount;

        emit DivestXChain(req.superformsData.superformIds, totalAmount, key);
    }

    /// @notice Divests assets from a single vault type across multiple chains
    /// @dev Processes withdrawals for the same vault type on different chains
    /// @param req The multi-chain single vault withdrawal request parameters
    /// @return totalAmount The total value of shares being withdrawn
    function divestMultiXChainSingleVault(MultiDstSingleVaultStateReq memory req)
        external
        payable
        onlyVault
        refundGas
        returns (uint256 totalAmount)
    {
        for (uint256 i = 0; i < req.superformsData.length;) {
            uint256 superformId = req.superformsData[i].superformId;
            bytes memory key = abi.encode(superformId);
            address receiver = getReceiver(address(this), key);

            req.superformsData[i].receiverAddress = receiver;

            // Retrieve the vault data for the target vault
            VaultData memory vaultObj = vault.getVault(superformId);
            // Cant invest in a vault that is not in the portfolio
            if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();
            uint256 amount = vaultObj.convertToAssets(req.superformsData[i].amount, true);

            totalAmount += amount;

            superPositions.safeTransferFrom(address(vault), address(this), superformId, amount, "");

            uint256[] memory superformIds = new uint256[](1);

            superformIds[0] = superformId;

            emit DivestXChain(superformIds, amount, key);

            unchecked {
                ++i;
            }
        }

        superformRouter.multiDstSingleVaultDeposit{ value: msg.value }(req);
        totalPendingXChainDivests += totalAmount;
        return totalAmount;
    }

    /// @notice Divests assets from multiple vaults across multiple chains
    /// @dev Processes withdrawals for different vault types across multiple chains
    /// @param req The multi-chain multi-vault withdrawal request parameters
    /// @return totalAmount The total value of shares being withdrawn
    function divestMultiXChainMultiVault(MultiDstMultiVaultStateReq memory req)
        external
        payable
        onlyVault
        refundGas
        returns (uint256 totalAmount)
    {
        for (uint256 i = 0; i < req.superformsData.length; i++) {
            uint256[] memory superformIds = req.superformsData[i].superformIds;
            uint256[] memory amounts = req.superformsData[i].amounts;
            bytes memory key = abi.encode(superformIds);
            address receiver = getReceiver(address(this), key);
            req.superformsData[i].receiverAddress = receiver;
            superPositions.safeBatchTransferFrom(address(vault), address(this), superformIds, amounts, "");
            uint256 totalChainAmount;

            for (uint256 j = 0; j < superformIds.length; j++) {
                uint256 superformId = superformIds[j];

                // Cant invest in a vault that is not in the portfolio
                VaultData memory vaultObj = vault.getVault(superformId);
                if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();

                uint256 amount = vaultObj.convertToAssets(amounts[j], true);

                totalAmount += amount;
                totalChainAmount += amount;
            }
            emit DivestXChain(superformIds, totalChainAmount, key);
        }
        superformRouter.multiDstMultiVaultDeposit{ value: msg.value }(req);
        totalPendingXChainDivests += totalAmount;
        return totalAmount;
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
        SingleXChainSingleVaultWithdraw memory config,
        uint256 totalRequestedAssets
    )
        external
        payable
        onlyVault
        refundGas
    {
        superPositions.safeTransferFrom(address(vault), address(this), superformId, amount, "");
        bytes memory key = abi.encode(superformId);
        SingleXChainSingleVaultStateReq memory params = SingleXChainSingleVaultStateReq({
            ambIds: config.ambIds,
            dstChainId: chainId,
            superformData: SingleVaultSFData({
                superformId: superformId,
                amount: amount,
                outputAmount: config.outputAmount,
                maxSlippage: config.maxSlippage,
                liqRequest: config.liqRequest,
                permit2data: "",
                hasDstSwap: config.hasDstSwap,
                retain4626: false,
                receiverAddress: getReceiver(receiver, key),
                receiverAddressSP: address(0),
                extraFormData: ""
            })
        });
        superformRouter.singleXChainSingleVaultWithdraw{ value: config.value }(params);
        requestedAssets[receiver][key] += totalRequestedAssets;
        uint256[] memory superformIds = new uint256[](1);
        superformIds[0] = superformId;
        emit LiquidateXChain(receiver, superformIds, totalRequestedAssets, key);
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
        SingleXChainMultiVaultWithdraw memory config,
        uint256 totalRequestedAssets
    )
        external
        payable
        onlyVault
        refundGas
    {
        uint256 len = superformIds.length;
        bytes memory key = abi.encode(superformIds);
        superPositions.safeBatchTransferFrom(address(vault), address(this), superformIds, amounts, "");
        SingleXChainMultiVaultStateReq memory params = SingleXChainMultiVaultStateReq({
            ambIds: config.ambIds,
            dstChainId: chainId,
            superformsData: MultiVaultSFData({
                superformIds: superformIds,
                amounts: amounts,
                outputAmounts: config.outputAmounts,
                maxSlippages: config.maxSlippages,
                liqRequests: config.liqRequests,
                permit2data: "",
                hasDstSwaps: config.hasDstSwaps,
                retain4626s: _getEmptyBoolArray(len),
                receiverAddress: getReceiver(receiver, key),
                receiverAddressSP: address(0),
                extraFormData: ""
            })
        });
        superformRouter.singleXChainMultiVaultWithdraw{ value: config.value }(params);
        requestedAssets[receiver][key] += totalRequestedAssets;
        emit LiquidateXChain(receiver, superformIds, totalRequestedAssets, key);
    }

    /// @dev Initiates withdrawals from a single vault on multiple different chains
    /// @param ambIds Array of AMB (Asset Management Bridge) IDs for each chain
    /// @param dstChainIds Array of destination chain IDs
    /// @param singleVaultDatas Array of SingleVaultSFData structures for each withdrawal
    function liquidateMultiDstSingleVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        SingleVaultSFData[] memory singleVaultDatas,
        uint256[] memory totalRequestedAssets
    )
        external
        payable
        onlyVault
        refundGas
    {
        for (uint256 i = 0; i < singleVaultDatas.length;) {
            uint256 superformId = singleVaultDatas[i].superformId;
            uint256[] memory superformIds = new uint256[](1);
            superformIds[0] = superformId;
            bytes memory key = abi.encode(superformId);
            singleVaultDatas[i].receiverAddress = getReceiver(singleVaultDatas[i].receiverAddress, key);
            requestedAssets[singleVaultDatas[i].receiverAddress][key] = totalRequestedAssets[i];
            superPositions.safeTransferFrom(address(vault), address(this), superformId, singleVaultDatas[i].amount, "");
            emit LiquidateXChain(singleVaultDatas[i].receiverAddress, superformIds, totalRequestedAssets[i], key);
            unchecked {
                ++i;
            }
        }
        MultiDstSingleVaultStateReq memory params =
            MultiDstSingleVaultStateReq({ ambIds: ambIds, dstChainIds: dstChainIds, superformsData: singleVaultDatas });
        superformRouter.multiDstSingleVaultWithdraw{ value: msg.value }(params);
    }

    /// @dev Initiates withdrawals from multiple vaults on multiple different chains
    /// @param ambIds Array of AMB (Asset Management Bridge) IDs for each chain
    /// @param dstChainIds Array of destination chain IDs
    /// @param multiVaultDatas Array of MultiVaultSFData structures for each chain's withdrawals
    function liquidateMultiDstMultiVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        MultiVaultSFData[] memory multiVaultDatas,
        uint256[] memory totalRequestedAssets
    )
        external
        payable
        onlyVault
        refundGas
    {
        for (uint256 i = 0; i < multiVaultDatas.length;) {
            uint256[] memory superformIds = multiVaultDatas[i].superformIds;
            bytes memory key = abi.encode(superformIds);
            multiVaultDatas[i].receiverAddress = getReceiver(multiVaultDatas[i].receiverAddress, key);
            requestedAssets[multiVaultDatas[i].receiverAddress][key] += totalRequestedAssets[i];
            superPositions.safeBatchTransferFrom(
                address(vault), address(this), superformIds, multiVaultDatas[i].amounts, ""
            );
            emit LiquidateXChain(multiVaultDatas[i].receiverAddress, superformIds, totalRequestedAssets[i], key);
            unchecked {
                ++i;
            }
        }
        MultiDstMultiVaultStateReq memory params =
            MultiDstMultiVaultStateReq({ ambIds: ambIds, dstChainIds: dstChainIds, superformsData: multiVaultDatas });
        superformRouter.multiDstMultiVaultWithdraw{ value: msg.value }(params);
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
        value;
        data;
        if (from == address(vault)) return this.onERC1155Received.selector;
        if (from != address(0)) revert Unauthorized();
        VaultData memory vaultObj = vault.getVault(superformId);
        uint256 investedAssets = pendingXChainInvests[superformId];
        delete pendingXChainInvests[superformId];
        uint256 bridgedAssets = vaultObj.convertToAssets(value, false);
        totalpendingXChainInvests -= investedAssets;
        superPositions.safeTransferFrom(address(this), address(vault), superformId, value, "");
        vault.settleXChainInvest(superformId, bridgedAssets);
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
    function getReceiver(address controller, bytes memory key) public returns (address receiverAddress) {
        address current = receivers[controller][key];
        if (current != address(0)) {
            return current;
        } else {
            receiverAddress =
                LibClone.clone(receiverImplementation, abi.encodeWithSignature("initialize(address)", controller, key));
            receivers[controller][key] = receiverAddress;
        }
    }

    /// @notice Settles a cross-chain liquidation by processing received assets
    /// @dev Pulls assets from the receiver contract and fulfills the settlement in the vault.
    /// Only callable by addresses with RELAYER_ROLE. The key for lookup is generated based on
    /// whether it's a single vault (superformId) or multiple vaults (array of superformIds).
    /// @param controller The address that initiated the liquidation
    /// @param superformIds Array of Superform IDs involved in the liquidation
    function settleLiquidation(address controller, uint256[] calldata superformIds) external onlyRoles(RELAYER_ROLE) {
        bytes memory key;
        if (superformIds.length == 1) {
            key = abi.encode(superformIds[0]);
        } else {
            key = abi.encode(superformIds);
        }
        ERC20Receiver receiverContract = ERC20Receiver(getReceiver(controller, key));
        uint256 settledAssets = receiverContract.balance();
        uint256 requestedAssets = requestedAssets[controller][key];
        receiverContract.pull(settledAssets);
        asset.safeTransfer(address(vault), settledAssets);
        vault.fulfillSettledRequest(controller, requestedAssets, settledAssets);
    }

    /// @notice Settles a cross-chain divestment by processing received assets
    /// @dev Pulls assets from the receiver contract and updates the vault's state.
    /// Only callable by addresses with RELAYER_ROLE. The key for lookup is generated based on
    /// whether it's a single vault (superformId) or multiple vaults (array of superformIds).
    /// For each Superform ID involved, notifies the vault of the settlement.
    /// @param superformIds Array of Superform IDs involved in the divestment
    function settleDivest(uint256[] calldata superformIds) external onlyRoles(RELAYER_ROLE) {
        bytes memory key;
        if (superformIds.length == 1) {
            key = abi.encode(superformIds[0]);
        } else {
            key = abi.encode(superformIds);
        }
        ERC20Receiver receiverContract = ERC20Receiver(getReceiver(address(this), key));
        uint256 settledAssets = receiverContract.balance();

        receiverContract.pull(settledAssets);
        totalPendingXChainDivests -= settledAssets;
        asset.safeTransfer(address(vault), settledAssets);
        for (uint256 i = 0; i < superformIds.length;) {
            vault.settleXChainDivest(superformIds[i], settledAssets);
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Helper function to get a empty bools array
    function _getEmptyBoolArray(uint256 len) private pure returns (bool[] memory) {
        return new bool[](len);
    }
}
