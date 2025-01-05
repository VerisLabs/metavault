/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ERC20Receiver } from "./ERC20Receiver.sol";
import { IBaseRouter, IMetaVault, ISuperPositions } from "interfaces/Lib.sol";

import { OwnableRoles } from "solady/auth/OwnableRoles.sol";

import { EnumerableSetLib } from "solady/utils/EnumerableSetLib.sol";
import { Initializable } from "solady/utils/Initializable.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import {
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
    VaultLib
} from "types/Lib.sol";

/// @title SuperformGateway
/// @author Unlockd
/// @notice Gateway contract that handles cross-chain communication between MetaVault and Superform protocol
/// @dev Manages deposits and withdrawals across different chains through Superform's infrastructure
contract SuperformGateway is Initializable, OwnableRoles {
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;
    using VaultLib for VaultData;
    using SafeTransferLib for address;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when there are pending cross-chain deposits
    error XChainDepositsPending();
    /// @notice Thrown when there are pending cross-chain withdrawals
    error XChainWithdrawsPending();
    /// @notice Thrown when attempting to interact with an unlisted vault
    error VaultNotListed();
    /// @notice Thrown when an invalid receiver address is provided
    error InvalidReceiver();
    /// @notice Thrown when an invalid request key is provided
    error InvalidKey();
    /// @notice Thrown when an invalid amount is provided
    error InvalidAmount();
    /// @notice Thrown when an invalid superform ID is provided
    error InvalidSuperformId();
    /// @notice Thrown when an invalid request ID is provided
    error InvalidRequestId();
    /// @notice Thrown when an invalid controller address is provided
    error InvalidController();
    /// @notice Thrown when a request is not found
    error RequestNotFound();
    /// @notice Thrown when a request has already been processed
    error RequestAlreadyProcessed();
    /// @notice Thrown when minimum balance requirements are not met
    error MinimumBalanceNotMet();
    /// @notice Thrown when an invalid recovery address is provided
    error InvalidRecoveryAddress();
    /// @notice Thrown when total amounts do not match
    error TotalAmountMismatch();
    /// @notice Thrown when a refund operation fails
    error RefundFailed();
    /// @notice Thrown when an asset transfer fails
    error AssetTransferFailed();
    /// @notice Thrown when a SuperPositions transfer fails
    error SuperPositionsTransferFailed();
    /// @notice Thrown when a settlement operation fails
    error SettlementFailed();
    /// @notice Thrown when insufficient gas is provided
    error InsufficientGas();
    /// @notice Thrown when ETH transfer fails
    error ETHTransferFailed();
    /// @notice Thrown when no requests are pending
    error NoRequestsPending();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a cross-chain liquidation is initiated
    /// @param controller The address initiating the liquidation
    /// @param superformIds Array of Superform IDs involved
    /// @param requestedAssets Total amount of assets requested
    /// @param key Unique identifier for the liquidation assets receiver contract
    event LiquidateXChain(
        address indexed controller, uint256[] indexed superformIds, uint256 indexed requestedAssets, bytes32 key
    );

    /// @notice Emitted when a cross-chain divestment is initiated
    /// @param superformIds Array of Superform IDs being divested
    /// @param requestedAssets Total amount of assets requested
    /// @param key Unique identifier for the divest assets receiver contract
    event DivestXChain(uint256[] indexed superformIds, uint256 indexed requestedAssets, bytes32 key);

    /// @notice Emitted when the recovery address is updated
    event RecoveryAddressUpdated(address indexed oldAddress, address indexed newAddress);

    /// @notice Emitted when a new request is created
    event RequestCreated(bytes32 indexed key, address indexed controller, uint256[] superformIds);

    /// @notice Emitted when a request is settled
    event RequestSettled(bytes32 indexed key, address indexed controller, uint256 settledAmount);

    /// @notice Emitted when a request is refunded
    event RequestRefunded(bytes32 indexed key, uint256 indexed superformId, uint256 value);

    /// @notice Emitted when an investment fails
    event InvestFailed(uint256 indexed superformId, uint256 refundedAssets);

    /// @notice Emitted when a new receiver contract is deployed
    event ReceiverDeployed(bytes32 indexed key, address indexed receiver);

    /// @notice Emitted when fees are paid
    event FeesPaid(uint256 gasUsed, uint256 feeAmount);

    /// @notice Emitted when assets are recovered
    event AssetRecovered(address indexed token, address indexed to, uint256 amount);

    /// @notice Emitted when SuperPositions are recovered
    event SuperPositionsRecovered(uint256 indexed superformId, address indexed to, uint256 amount);

    /// @notice Emitted when pending invest amount is updated
    event PendingInvestUpdated(uint256 indexed superformId, uint256 oldAmount, uint256 newAmount);

    /// @notice Emitted when pending divest amount is updated
    event PendingDivestUpdated(uint256 oldAmount, uint256 newAmount);

    /*//////////////////////////////////////////////////////////////
                            DATA STRUCTURES
    //////////////////////////////////////////////////////////////*/

    /// @notice Data structure for cross-chain requests
    /// @param controller Address controlling the request
    /// @param superformIds Array of Superform IDs involved in request
    /// @param requestedAssetsPerVault Array of requested assets per vault
    /// @param requestedAssets Total requested assets
    /// @param receiverAddress Address to receive assets
    struct RequestData {
        address controller;
        uint256[] superformIds;
        uint256[] requestedAssetsPerVault;
        uint256 requestedAssets;
        address receiverAddress;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Role identifier for admin privileges
    uint256 public constant ADMIN_ROLE = _ROLE_0;

    /// @notice Role identifier for relayer
    uint256 public constant RELAYER_ROLE = _ROLE_0;

    /// @notice ERC20Receiver contract implementation to clone
    address public receiverImplementation;

    /// @notice Receiver address for invests
    address public receiverAddress;

    /// @notice Superpositions contract interface
    ISuperPositions public superPositions;

    /// @notice Superform router interface
    IBaseRouter public superformRouter;

    /// @notice Underlying vault interface
    IMetaVault public vault;

    /// @notice Asset address
    address public asset;

    /// @notice Recovery address for failed transactions
    address public recoveryAddress;

    /// @notice Mapping of request keys to receiver addresses
    mapping(bytes32 => address) public receivers;

    /// @notice Total pending cross-chain investments
    uint256 public totalpendingXChainInvests;

    /// @notice Mapping of superform IDs to pending investment amounts
    mapping(uint256 => uint256) public pendingXChainInvests;

    /// @notice Total pending cross-chain divests
    uint256 public totalPendingXChainDivests;

    /// @notice Queue of all active requests
    EnumerableSetLib.Bytes32Set private _requestsQueue;

    /// @notice Mapping of controller addresses to nonces
    mapping(address => uint256) nonces;

    /// @notice Mapping of request keys to request data
    mapping(bytes32 => RequestData) public requests;

    /// @notice Gap for upgradeability
    uint256[20] private __gap;

    /// @notice Contract constructor
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
        receiverImplementation = address(new ERC20Receiver(asset, address(superPositions)));

        // Set up approvals
        asset.safeApprove(address(superformRouter), type(uint256).max);
        asset.safeApprove(address(vault), type(uint256).max);
        superPositions.setApprovalForAll(address(superformRouter), true);

        // Initialize ownership and grant admin role
        _initializeOwner(msg.sender);
        _grantRoles(msg.sender, ADMIN_ROLE);
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

    /// @notice Sets the recovery address for the contract
    /// @dev Only callable by admin role
    /// @param _newRecoveryAddress The new recovery address to set
    function setRecoveryAddress(address _newRecoveryAddress) external onlyRoles(ADMIN_ROLE) {
        if (_newRecoveryAddress == address(0)) revert InvalidRecoveryAddress();
        address oldAddress = recoveryAddress;
        recoveryAddress = _newRecoveryAddress;
        emit RecoveryAddressUpdated(oldAddress, _newRecoveryAddress);
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

        req.superformData.receiverAddressSP = recoveryAddress;
        // Initiate the cross-chain deposit via the vault router
        superformRouter.singleXChainSingleVaultDeposit{ value: msg.value }(req);

        uint256 oldPendingAmount = pendingXChainInvests[superformId];
        pendingXChainInvests[superformId] += amount;
        uint256 oldTotalPending = totalpendingXChainInvests;
        totalpendingXChainInvests += amount;
        emit PendingInvestUpdated(superformId, oldPendingAmount, pendingXChainInvests[superformId]);
        emit PendingInvestUpdated(0, oldTotalPending, totalpendingXChainInvests);
    }

    /// @notice Invests assets into multiple vaults across a chain
    /// @dev Processes multi-vault deposits and updates pending investment tracking
    /// @param req The cross-chain multi-vault deposit request parameters
    /// @return totalAmount The total amount of assets invested
    function investSingleXChainMultiVault(SingleXChainMultiVaultStateReq memory req)
        external
        payable
        onlyVault
        refundGas
        returns (uint256 totalAmount)
    {
        if (req.superformsData.superformIds.length == 0) revert InvalidAmount();
        if (req.superformsData.superformIds.length != req.superformsData.amounts.length) revert TotalAmountMismatch();
        req.superformsData.receiverAddressSP = address(this);
        for (uint256 i = 0; i < req.superformsData.superformIds.length; ++i) {
            uint256 superformId = req.superformsData.superformIds[i];

            if (recoveryAddress == address(0)) revert InvalidRecoveryAddress();
            req.superformsData.receiverAddressSP = recoveryAddress;

            uint256 amount = req.superformsData.amounts[i];

            uint256 oldPendingAmount = pendingXChainInvests[superformId];
            pendingXChainInvests[superformId] += amount;
            emit PendingInvestUpdated(superformId, oldPendingAmount, amount);

            totalAmount += amount;

            // Cant invest in a vault that is not in the portfolio
            VaultData memory vaultObj = vault.getVault(superformId);
            if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();
        }
        uint256 oldTotalPending = totalpendingXChainInvests;
        totalpendingXChainInvests += totalAmount;
        emit PendingInvestUpdated(0, oldTotalPending, totalpendingXChainInvests);
        asset.safeTransferFrom(address(vault), address(this), totalAmount);
        superformRouter.singleXChainMultiVaultDeposit{ value: msg.value }(req);
    }

    /// @notice Invests assets in a single vault across multiple chains
    /// @dev Handles multi-destination deposits for a single vault type
    /// @param req The multi-destination single vault deposit request
    /// @return totalAmount The total amount of assets invested
    function investMultiXChainSingleVault(MultiDstSingleVaultStateReq memory req)
        external
        payable
        onlyVault
        refundGas
        returns (uint256 totalAmount)
    {
        if (req.superformsData.length == 0) revert InvalidAmount();
        for (uint256 i = 0; i < req.superformsData.length;) {
            uint256 superformId = req.superformsData[i].superformId;
            uint256 amount = req.superformsData[i].amount;

            if (recoveryAddress == address(0)) revert InvalidRecoveryAddress();
            req.superformsData[i].receiverAddressSP = recoveryAddress;

            // Cant invest in a vault that is not in the portfolio
            VaultData memory vaultObj = vault.getVault(superformId);
            if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();
            uint256 oldPendingAmount = pendingXChainInvests[superformId];
            pendingXChainInvests[superformId] = amount;
            emit PendingInvestUpdated(superformId, oldPendingAmount, amount);

            totalAmount += amount;
            unchecked {
                ++i;
            }
        }
        asset.safeTransferFrom(address(vault), address(this), totalAmount);
        superformRouter.multiDstSingleVaultDeposit{ value: msg.value }(req);
        uint256 oldTotalPending = totalpendingXChainInvests;
        totalpendingXChainInvests += totalAmount;
        emit PendingInvestUpdated(0, oldTotalPending, totalpendingXChainInvests);
    }

    /// @notice Invests assets in multiple vaults across multiple chains
    /// @dev Processes multi-vault multi-chain deposits
    /// @param req The multi-destination multi-vault deposit request
    /// @return totalAmount The total amount of assets invested
    function investMultiXChainMultiVault(MultiDstMultiVaultStateReq memory req)
        external
        payable
        onlyVault
        refundGas
        returns (uint256 totalAmount)
    {
        if (req.superformsData.length == 0) revert InvalidAmount();

        for (uint256 i = 0; i < req.superformsData.length; i++) {
            uint256[] memory superformIds = req.superformsData[i].superformIds;
            uint256[] memory amounts = req.superformsData[i].amounts;

            if (superformIds.length != amounts.length) revert TotalAmountMismatch();
            for (uint256 j = 0; j < superformIds.length; j++) {
                uint256 superformId = superformIds[j];
                uint256 amount = amounts[j];

                if (recoveryAddress == address(0)) revert InvalidRecoveryAddress();
                req.superformsData[i].receiverAddressSP = recoveryAddress;

                // Cant invest in a vault that is not in the portfolio
                VaultData memory vaultObj = vault.getVault(superformId);
                if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();
                uint256 oldPendingAmount = pendingXChainInvests[superformId];
                pendingXChainInvests[superformId] = amount;
                emit PendingInvestUpdated(superformId, oldPendingAmount, amount);
                totalAmount += amount;
            }
        }
        uint256 oldTotalPending = totalpendingXChainInvests;
        totalpendingXChainInvests += totalAmount;
        asset.safeTransferFrom(address(vault), address(this), totalAmount);
        superformRouter.multiDstMultiVaultDeposit{ value: msg.value }(req);
        emit PendingInvestUpdated(0, oldTotalPending, totalpendingXChainInvests);
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
        if (superformId == 0) revert InvalidSuperformId();

        bytes32 key = keccak256(abi.encode(address(vault), nonces[address(vault)]++, superformId));
        _requestsQueue.add(key);

        address receiver = getReceiver(key);
        if (receiver == address(0)) revert InvalidReceiver();

        ERC20Receiver(receiver).setMinExpectedBalance(req.superformData.outputAmount);

        VaultData memory vaultObj = vault.getVault(superformId);
        if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();

        req.superformData.receiverAddress = receiver;

        // Update the vault's internal accounting
        sharesValue = vaultObj.convertToAssets(req.superformData.amount, true);

        if (sharesValue == 0) revert InvalidAmount();

        uint256 oldAmount = totalPendingXChainDivests;
        totalPendingXChainDivests += sharesValue;
        emit PendingDivestUpdated(oldAmount, totalPendingXChainDivests);

        superPositions.safeTransferFrom(address(vault), address(this), superformId, req.superformData.amount, "");

        superformRouter.singleXChainSingleVaultWithdraw{ value: msg.value }(req);

        uint256[] memory superformIds = new uint256[](1);
        superformIds[0] = superformId;

        RequestData storage data = requests[key];
        data.controller = address(vault);
        data.receiverAddress = receiver;
        data.superformIds = superformIds;
        data.requestedAssets = sharesValue;
        data.requestedAssetsPerVault.push(sharesValue);

        emit RequestCreated(key, address(vault), superformIds);
        emit DivestXChain(superformIds, sharesValue, key);

        return sharesValue;
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
        if (req.superformsData.superformIds.length == 0) revert InvalidAmount();
        if (req.superformsData.superformIds.length != req.superformsData.amounts.length) revert TotalAmountMismatch();

        uint256 totalExpectedAmount;
        for (uint256 i = 0; i < req.superformsData.superformIds.length; ++i) {
            uint256 superformId = req.superformsData.superformIds[i];
            if (superformId == 0) revert InvalidSuperformId();

            // Cant invest in a vault that is not in the portfolio
            VaultData memory vaultObj = vault.getVault(superformId);
            if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();

            uint256 amount = vaultObj.convertToAssets(req.superformsData.amounts[i], true);
            if (amount == 0) revert InvalidAmount();

            totalExpectedAmount += req.superformsData.outputAmounts[i];
            // Update the vault's internal accounting
            totalAmount += amount;
        }

        bytes32 key = keccak256(abi.encode(address(vault), nonces[address(vault)]++, req.superformsData.superformIds));
        _requestsQueue.add(key);
        address receiver = getReceiver(key);

        ERC20Receiver(receiver).setMinExpectedBalance(totalExpectedAmount);
        RequestData storage data = requests[key];
        data.controller = address(vault);
        data.receiverAddress = receiver;
        data.superformIds = req.superformsData.superformIds;
        data.requestedAssets = totalAmount;
        req.superformsData.receiverAddress = receiver;

        superPositions.safeBatchTransferFrom(
            address(vault), address(this), req.superformsData.superformIds, req.superformsData.amounts, ""
        );
        superformRouter.singleXChainMultiVaultWithdraw{ value: msg.value }(req);
        uint256 oldPendingDivests = totalPendingXChainDivests;
        totalPendingXChainDivests += totalAmount;

        emit PendingDivestUpdated(oldPendingDivests, totalPendingXChainDivests);
        emit RequestCreated(key, address(vault), req.superformsData.superformIds);
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
        uint256 totalExpectedAmount;
        for (uint256 i = 0; i < req.superformsData.length;) {
            uint256 superformId = req.superformsData[i].superformId;

            uint256[] memory superformIds = new uint256[](1);

            superformIds[0] = superformId;

            bytes32 key = keccak256(abi.encode(address(vault), nonces[address(vault)]++, superformId));
            _requestsQueue.add(key);
            address receiver = getReceiver(key);

            RequestData storage data = requests[key];
            data.controller = address(vault);
            data.receiverAddress = receiver;
            data.superformIds = superformIds;
            data.requestedAssets = totalAmount;

            ERC20Receiver(receiver).setMinExpectedBalance(req.superformsData[i].outputAmount);
            req.superformsData[i].receiverAddress = receiver;

            // Retrieve the vault data for the target vault
            VaultData memory vaultObj = vault.getVault(superformId);
            // Cant invest in a vault that is not in the portfolio
            if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();
            uint256 amount = vaultObj.convertToAssets(req.superformsData[i].amount, true);

            totalAmount += amount;

            superPositions.safeTransferFrom(address(vault), address(this), superformId, amount, "");

            emit RequestCreated(key, address(vault), superformIds);
            emit DivestXChain(superformIds, amount, key);

            unchecked {
                ++i;
            }
        }

        superformRouter.multiDstSingleVaultDeposit{ value: msg.value }(req);
        uint256 oldPendingDivests = totalPendingXChainDivests;
        totalPendingXChainDivests += totalAmount;
        emit PendingDivestUpdated(oldPendingDivests, totalPendingXChainDivests);
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
            bytes32 key = keccak256(abi.encode(address(vault), nonces[address(vault)]++, superformIds));
            _requestsQueue.add(key);
            address receiver = getReceiver(key);
            RequestData storage data = requests[key];
            data.controller = address(vault);
            data.receiverAddress = receiver;
            data.superformIds = superformIds;
            data.requestedAssets = totalAmount;
            req.superformsData[i].receiverAddress = receiver;
            superPositions.safeBatchTransferFrom(address(vault), address(this), superformIds, amounts, "");
            uint256 totalChainAmount;

            uint256 totalExpectedAmount;
            for (uint256 j = 0; j < superformIds.length; j++) {
                uint256 superformId = superformIds[j];

                // Cant invest in a vault that is not in the portfolio
                VaultData memory vaultObj = vault.getVault(superformId);
                if (!vault.isVaultListed(vaultObj.vaultAddress)) revert VaultNotListed();

                uint256 amount = vaultObj.convertToAssets(amounts[j], true);
                totalExpectedAmount += req.superformsData[i].outputAmounts[j];
                totalAmount += amount;
                totalChainAmount += amount;
            }
            ERC20Receiver(receiver).setMinExpectedBalance(totalExpectedAmount);
            emit RequestCreated(key, address(vault), superformIds);
            emit DivestXChain(superformIds, totalChainAmount, key);
        }
        superformRouter.multiDstMultiVaultDeposit{ value: msg.value }(req);
        uint256 oldPendingDivests = totalPendingXChainDivests;
        totalPendingXChainDivests += totalAmount;
        emit PendingDivestUpdated(oldPendingDivests, totalPendingXChainDivests);
        return totalAmount;
    }

    /// @dev Initiates a withdrawal from a single vault on a different chain
    /// @param chainId ID of the destination chain
    /// @param superformId ID of the superform to withdraw from
    /// @param amount Amount of shares to withdraw
    /// @param controller Address to receive the withdrawn assets
    /// @param config Configuration for the cross-chain withdrawal
    function liquidateSingleXChainSingleVault(
        uint64 chainId,
        uint256 superformId,
        uint256 amount,
        address controller,
        SingleXChainSingleVaultWithdraw memory config,
        uint256 totalRequestedAssets
    )
        external
        payable
        onlyVault
        refundGas
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](1);
        superPositions.safeTransferFrom(address(vault), address(this), superformId, amount, "");
        bytes32 key = keccak256(abi.encode(controller, nonces[controller]++, superformId));
        _requestsQueue.add(key);
        requestIds[0] = key;
        address assetReceiver = getReceiver(key);
        ERC20Receiver(assetReceiver).setMinExpectedBalance(config.outputAmount);
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
                receiverAddress: assetReceiver,
                receiverAddressSP: address(0),
                extraFormData: ""
            })
        });
        superformRouter.singleXChainSingleVaultWithdraw{ value: config.value }(params);
        uint256[] memory superformIds = new uint256[](1);
        superformIds[0] = superformId;
        RequestData storage data = requests[key];
        data.requestedAssets = totalRequestedAssets;
        data.controller = controller;
        data.receiverAddress = assetReceiver;
        data.superformIds = superformIds;
        data.requestedAssetsPerVault.push(totalRequestedAssets);

        emit LiquidateXChain(controller, superformIds, totalRequestedAssets, key);
        return requestIds;
    }

    /// @dev Initiates withdrawals from multiple vaults on a single different chain
    /// @param chainId ID of the destination chain
    /// @param superformIds Array of superform IDs to withdraw from
    /// @param amounts Array of share amounts to withdraw from each superform
    /// @param controller Address to receive the withdrawn assets
    /// @param config Configuration for the cross-chain withdrawals
    function liquidateSingleXChainMultiVault(
        uint64 chainId,
        uint256[] memory superformIds,
        uint256[] memory amounts,
        address controller,
        SingleXChainMultiVaultWithdraw memory config,
        uint256 totalRequestedAssets,
        uint256[] memory requestedAssetsPerVault
    )
        external
        payable
        onlyVault
        refundGas
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](1);
        uint256 len = superformIds.length;
        bytes32 key = keccak256(abi.encode(controller, nonces[controller]++, superformIds));
        address assetReceiver = getReceiver(key);
        requestIds[0] = key;
        _requestsQueue.add(key);
        uint256 totalMinExpectedBalance;
        for (uint256 i = 0; i < config.outputAmounts.length; ++i) {
            totalMinExpectedBalance += config.outputAmounts[i];
        }
        ERC20Receiver(assetReceiver).setMinExpectedBalance(totalMinExpectedBalance);
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
                receiverAddress: assetReceiver,
                receiverAddressSP: address(0),
                extraFormData: ""
            })
        });
        superformRouter.singleXChainMultiVaultWithdraw{ value: config.value }(params);
        RequestData storage data = requests[key];
        data.requestedAssets = totalRequestedAssets;
        data.controller = controller;
        data.receiverAddress = assetReceiver;
        data.superformIds = superformIds;
        data.requestedAssetsPerVault = requestedAssetsPerVault;

        emit LiquidateXChain(controller, superformIds, totalRequestedAssets, key);
        return requestIds;
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
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](singleVaultDatas.length);
        for (uint256 i = 0; i < singleVaultDatas.length;) {
            uint256 superformId = singleVaultDatas[i].superformId;
            uint256[] memory superformIds = new uint256[](1);
            superformIds[0] = superformId;
            bytes32 key = keccak256(
                abi.encode(
                    singleVaultDatas[i].receiverAddress, nonces[singleVaultDatas[i].receiverAddress]++, superformId
                )
            );
            _requestsQueue.add(key);
            requestIds[i] = key;
            address controller = singleVaultDatas[i].receiverAddress;
            address assetReceiver = getReceiver(key);
            ERC20Receiver(assetReceiver).setMinExpectedBalance(singleVaultDatas[i].outputAmount);
            singleVaultDatas[i].receiverAddress = assetReceiver;
            RequestData storage data = requests[key];
            data.requestedAssets = totalRequestedAssets[i];
            data.controller = controller;
            data.receiverAddress = assetReceiver;
            data.superformIds = superformIds;
            data.requestedAssetsPerVault.push(totalRequestedAssets[i]);
            superPositions.safeTransferFrom(address(vault), address(this), superformId, singleVaultDatas[i].amount, "");
            emit LiquidateXChain(controller, superformIds, totalRequestedAssets[i], key);
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
        uint256[] memory totalRequestedAssets,
        uint256[][] memory requestedAssetsPerVault
    )
        external
        payable
        onlyVault
        refundGas
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](multiVaultDatas.length);
        for (uint256 i = 0; i < multiVaultDatas.length;) {
            uint256[] memory superformIds = multiVaultDatas[i].superformIds;
            address controller = multiVaultDatas[i].receiverAddress;
            bytes32 key = keccak256(abi.encode(controller, nonces[controller]++, superformIds));
            _requestsQueue.add(key);
            requestIds[i] = key;
            address assetReceiver = getReceiver(key);
            uint256 totalMinExpectedBalance;
            for (uint256 j = 0; j < multiVaultDatas[i].outputAmounts.length; j++) {
                totalMinExpectedBalance += multiVaultDatas[i].outputAmounts[j];
            }
            ERC20Receiver(assetReceiver).setMinExpectedBalance(totalMinExpectedBalance);
            multiVaultDatas[i].receiverAddress = assetReceiver;
            RequestData storage data = requests[key];
            data.requestedAssets = totalRequestedAssets[i];
            data.controller = controller;
            data.receiverAddress = assetReceiver;
            data.superformIds = superformIds;
            superPositions.safeBatchTransferFrom(
                address(vault), address(this), superformIds, multiVaultDatas[i].amounts, ""
            );
            data.requestedAssetsPerVault = requestedAssetsPerVault[i];
            emit LiquidateXChain(controller, superformIds, totalRequestedAssets[i], key);
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
        try ERC20Receiver(from).key() returns (bytes32 key) {
            if (requests[key].receiverAddress == from) {
                return this.onERC1155Received.selector;
            }
        } catch { }
        if (from != recoveryAddress) revert Unauthorized();
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

    /// @notice Handles refunds of SuperPositions when a cross-chain divestment fails
    /// @dev This function is called by the ERC20Receiver contract when a divestment fails and SuperPositions need to be
    /// returned
    ///      The function verifies the caller is a valid receiver, updates pending divest amounts, and transfers the
    /// SuperPositions back to the vault
    /// @param superformId The ID of the Superform position being refunded
    /// @param value The amount of SuperPositions being refunded
    function notifyRefund(uint256 superformId, uint256 value) external {
        bytes32 key = ERC20Receiver(msg.sender).key();
        if (requests[key].receiverAddress != msg.sender) revert();
        RequestData memory req = requests[key];
        uint256 currentExpectedBalance = ERC20Receiver(msg.sender).minExpectedBalance();
        uint256 vaultIndex;
        for (uint256 i = 0; i < req.superformIds.length; ++i) {
            if (req.superformIds[i] == superformId) {
                vaultIndex = i;
                break;
            }
        }
        uint256 vaultRequestedAssets = req.requestedAssetsPerVault[vaultIndex];
        if (req.controller == address(vault)) {
            totalPendingXChainDivests -= vaultRequestedAssets;
        }
        requests[key].requestedAssets -= vaultRequestedAssets;
        ERC20Receiver(msg.sender).setMinExpectedBalance(_sub0(currentExpectedBalance, vaultRequestedAssets));
        superPositions.safeTransferFrom(msg.sender, address(this), superformId, value, "");
        superPositions.safeTransferFrom(
            address(this), address(vault), superformId, value, abi.encode(vaultRequestedAssets)
        );
    }

    /// @dev Returns the delegatee of a owner to receive the assets
    /// @dev If it doesnt exist it deploys it at the moment
    /// @notice receiverAddress returns delegatee
    function getReceiver(bytes32 key) public returns (address receiverAddress) {
        if (key == bytes32(0)) revert InvalidKey();
        address current = receivers[key];
        if (current != address(0)) {
            return current;
        } else {
            receiverAddress = LibClone.clone(receiverImplementation);
            ERC20Receiver(receiverAddress).initialize(key);
            receivers[key] = receiverAddress;
            emit ReceiverDeployed(key, receiverAddress);
        }
    }

    /// @notice Settles a cross-chain liquidation by processing received assets
    /// @dev Pulls assets from the receiver contract and fulfills the settlement in the vault.
    /// Only callable by addresses with RELAYER_ROLE. The key for lookup is generated based on
    /// whether it's a single vault (superformId) or multiple vaults (array of superformIds).
    /// @param key identifier of the receiver contract
    function settleLiquidation(bytes32 key, bool force) external onlyRoles(RELAYER_ROLE) {
        if (!_requestsQueue.contains(key)) revert RequestNotFound();

        RequestData memory data = requests[key];
        if (data.controller == address(0)) revert InvalidController();

        ERC20Receiver receiverContract = ERC20Receiver(getReceiver(key));
        uint256 settledAssets = receiverContract.balance();
        uint256 requestedAssets = requests[key].requestedAssets;

        _requestsQueue.remove(key);

        if (!force) {
            if (receiverContract.balance() < receiverContract.minExpectedBalance()) {
                revert MinimumBalanceNotMet();
            }
        }

        receiverContract.pull(settledAssets);
        asset.safeTransfer(address(vault), settledAssets);
        vault.fulfillSettledRequest(data.controller, data.requestedAssets, settledAssets);
        emit RequestSettled(key, data.controller, settledAssets);
    }

    /// @notice Settles a cross-chain divestment by processing received assets
    /// @dev Pulls assets from the receiver contract and updates the vault's state.
    /// Only callable by addresses with RELAYER_ROLE. The key for lookup is generated based on
    /// whether it's a single vault (superformId) or multiple vaults (array of superformIds).
    /// For each Superform ID involved, notifies the vault of the settlement.
    /// @param key Identifier of the receiver contract
    function settleDivest(bytes32 key, bool force) external onlyRoles(RELAYER_ROLE) {
        if (!_requestsQueue.contains(key)) revert();
        RequestData memory data = requests[key];
        _requestsQueue.remove(key);
        ERC20Receiver receiverContract = ERC20Receiver(getReceiver(key));
        if (data.controller != address(vault)) revert();
        if (!force) {
            if (receiverContract.balance() < receiverContract.minExpectedBalance()) revert();
        }
        uint256 settledAssets = receiverContract.balance();
        uint256 requestedAssets = data.requestedAssets;
        receiverContract.pull(settledAssets);
        totalPendingXChainDivests -= settledAssets;
        asset.safeTransfer(address(vault), settledAssets);
        vault.settleXChainDivest(requestedAssets);
    }

    /// @notice Handles the cleanup and refund process for failed cross-chain investments
    /// @dev This function is called after assets are recovered from the recovery contract on the destination chain
    ///      It updates the pending investment tracking and processes any refunded assets
    ///      The refunded assets are donated back to the vault to maintain share price accuracy
    /// @param superformId The ID of the Superform position that failed to invest
    /// @param refundedAssets The amount of assets that were recovered and refunded from the destination chain
    function notifyFailedInvest(uint256 superformId, uint256 refundedAssets) external onlyRoles(RELAYER_ROLE) {
        if (superformId == 0) revert InvalidSuperformId();

        uint256 oldAmount = pendingXChainInvests[superformId];
        totalpendingXChainInvests -= oldAmount;
        pendingXChainInvests[superformId] = 0;

        emit PendingInvestUpdated(superformId, oldAmount, 0);
        emit InvestFailed(superformId, refundedAssets);

        if (refundedAssets > 0) {
            asset.safeTransferFrom(msg.sender, address(this), refundedAssets);
            vault.donate(refundedAssets);
        }
    }

    function previewLiquidateSingleXChainSingleVault(
        uint64 chainId,
        uint256 superformId,
        uint256 amount,
        address receiver,
        SingleXChainSingleVaultWithdraw memory config,
        uint256 totalRequestedAssets,
        uint256[] memory requestedAssetsPerVault
    )
        external
        view
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](1);
        bytes32 key = keccak256(abi.encode(receiver, nonces[receiver] + 1, superformId));
        requestIds[0] = key;
        return requestIds;
    }

    function previewLiquidateSingleXChainMultiVault(
        uint64 chainId,
        uint256[] memory superformIds,
        uint256[] memory amounts,
        address receiver,
        SingleXChainMultiVaultWithdraw memory config,
        uint256 totalRequestedAssets,
        uint256[] memory requestedAssetsPerVault
    )
        external
        view
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](1);
        bytes32 key = keccak256(abi.encode(receiver, nonces[receiver] + 1, superformIds));
        requestIds[0] = key;
        return requestIds;
    }

    function previewLiquidateMultiDstSingleVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        SingleVaultSFData[] memory singleVaultDatas,
        uint256[] memory totalRequestedAssets
    )
        external
        view
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](singleVaultDatas.length);
        for (uint256 i = 0; i < singleVaultDatas.length;) {
            uint256 superformId = singleVaultDatas[i].superformId;
            bytes32 key = keccak256(
                abi.encode(
                    singleVaultDatas[i].receiverAddress,
                    nonces[singleVaultDatas[i].receiverAddress] + i + 1,
                    superformId
                )
            );
            requestIds[i] = key;
            unchecked {
                ++i;
            }
        }
        return requestIds;
    }

    function previewLiquidateMultiDstMultiVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        MultiVaultSFData[] memory multiVaultDatas,
        uint256[] memory totalRequestedAssets,
        uint256[][] memory totalRequestedAssetsPerVault
    )
        external
        view
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](multiVaultDatas.length);
        for (uint256 i = 0; i < multiVaultDatas.length;) {
            uint256[] memory superformIds = multiVaultDatas[i].superformIds;
            bytes32 key = keccak256(
                abi.encode(
                    multiVaultDatas[i].receiverAddress, nonces[multiVaultDatas[i].receiverAddress] + i + 1, superformIds
                )
            );
            requestIds[i] = key;
            unchecked {
                ++i;
            }
        }
        return requestIds;
    }

    function previewIdDivestSingleXChainSingleVault(SingleXChainSingleVaultStateReq memory req)
        external
        view
        returns (bytes32 requestId)
    {
        uint256 superformId = req.superformData.superformId;
        return keccak256(abi.encode(address(vault), nonces[address(vault)] + 1, superformId));
    }

    function previewIdDivestMultiXChainSingleVault(SingleXChainMultiVaultStateReq memory req)
        external
        view
        returns (bytes32 requestId)
    {
        return keccak256(abi.encode(address(vault), nonces[address(vault)] + 1, req.superformsData.superformIds));
    }

    function previewIdDivestSingleXChainMultiVault(MultiDstSingleVaultStateReq memory req)
        external
        view
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](req.superformsData.length);
        for (uint256 i = 0; i < req.superformsData.length;) {
            uint256 superformId = req.superformsData[i].superformId;
            requestIds[i] = keccak256(abi.encode(address(vault), nonces[address(vault)] + i + 1, superformId));
        }
    }

    function previewIdDivestMultiXChainMultiVault(MultiDstMultiVaultStateReq memory req)
        external
        view
        returns (bytes32[] memory requestIds)
    {
        requestIds = new bytes32[](req.superformsData.length);
        for (uint256 i = 0; i < req.superformsData.length; i++) {
            uint256[] memory superformIds = req.superformsData[i].superformIds;
            requestIds[i] = keccak256(abi.encode(address(vault), nonces[address(vault)] + i + 1, superformIds));
        }
    }

    /// @notice Gets the current queue of pending request IDs
    /// @dev Returns an array of all active request IDs in the queue
    /// @return requestIds Array of pending request IDs
    function getRequestsQueue() public view returns (bytes32[] memory requestIds) {
        return _requestsQueue.values();
    }

    /// @dev Helper function to get a empty bools array
    function _getEmptyBoolArray(uint256 len) private pure returns (bool[] memory) {
        return new bool[](len);
    }

    /// @dev Private helper to substract a - b or return 0 if it underflows
    function _sub0(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            return a - b > a ? 0 : a - b;
        }
    }
}
