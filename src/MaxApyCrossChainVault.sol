/// SPDX-License-Identifer: MIT
pragma solidity 0.8.19;

import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";
import { Multicallable } from "solady/utils/Multicallable.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";
import { ERC20Receiver } from "crosschain/Lib.sol";
import { ISuperPositions, IBaseRouter, ISuperformFactory, IERC4626Oracle } from "interfaces/Lib.sol";
import { ERC7540, ReentrancyGuard } from "lib/Lib.sol";
import {
    VaultData,
    VaultReport,
    VaultLib,
    LiqRequest,
    MultiVaultSFData,
    SingleVaultSFData,
    MultiDstMultiVaultStateReq,
    SingleXChainMultiVaultStateReq,
    MultiDstSingleVaultStateReq,
    SingleXChainSingleVaultStateReq,
    SingleDirectSingleVaultStateReq,
    SingleDirectMultiVaultStateReq,
    SingleXChainSingleVaultWithdraw,
    SingleXChainMultiVaultWithdraw,
    MultiXChainSingleVaultWithdraw,
    MultiXChainMultiVaultWithdraw
} from "types/Lib.sol";
import "forge-std/Test.sol";

/// @title MaxApyCrossChainVault
/// @author Unlockd
/// @notice A ERC750 vault implementation for cross-chain yield
/// aggregation
contract MaxApyCrossChainVault is ERC7540, OwnableRoles, ReentrancyGuard, Multicallable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           LIBRARIES                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Safe casting operations for uint256
    using SafeCastLib for uint256;

    /// @dev Safe transfer operations for ERC20 tokens
    using SafeTransferLib for address;

    /// @dev Library for vault-related operations
    using VaultLib for VaultData;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Emitted when a redeem request is processed
    event ProcessRedeemRequest(address indexed controller, uint256 shares);

    /// @dev Emitted when a redeem request is fulfilled after being processed
    event FulfillRedeemRequest(address indexed controller, uint256 shares, uint256 assets);

    /// @dev Emitted when investing vault idle assets
    event Invest(uint256 amount);

    /// @dev Emitted when cross-chain investment is settled
    event SettleXChainInvest(uint256 indexed superformId, uint256 assets);

    /// @dev Emitted when investing vault idle assets
    event Report(uint64 indexed chainId, address indexed vault, int256 amount);

    /// @dev Emitted when adding a new vault to the portfolio
    event AddVault(uint64 indexed chainId, address vault);

    /// @dev Emitted when setting a new oracle for a chain
    event SetOracle(uint64 indexed chainId, address oracle);

    /// @dev Emitted when updating the shares lock time
    event SetSharesLockTime(uint24 time);

    /// @dev Emitted when updating the management fee
    event SetManagementFee(uint16 fee);

    /// @dev Emitted when updating the oracle fee
    event SetOracleFee(uint16 fee);

    /// @dev Emitted when the emergency shutdown state is changed
    event EmergencyShutdown(bool enabled);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Thrown when attempting to interact with a vault that is not listed in the portfolio
    error VaultNotListed();

    /// @notice Thrown when attempting to add a vault that is already listed
    error VaultAlreadyListed();

    /// @notice Thrown when trying to perform an operation while cross-chain deposits are still pending
    error XChainDepositsPending();

    /// @notice Thrown when attempting to withdraw more assets than are currently available
    error InsufficientAvailableAssets();

    /// @notice Thrown when trying to perform an operation on a request that has not been settled yet
    error RequestNotSettled();

    /// @notice Thrown when trying to redeem a non processed request
    error RedeemNotProcessed();

    /// @notice Thrown when attempting to redeem shares that are still locked
    error SharesLocked();

    /// @notice Thrown when there are not enough assets to fulfill a request
    error InsufficientAssets();

    /// @notice Thrown when attempting to perform an operation while the vault is in emergency shutdown
    error VaultShutdown();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           CONSTANTS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Maximum size of the withdrawal queue
    uint256 public constant WITHDRAWAL_QUEUE_SIZE = 30;

    /// @notice Number of seconds in a year, used for APY calculations
    uint256 public constant SECS_PER_YEAR = 31_556_952;

    /// @notice Maximum basis points (100%)
    uint256 public constant MAX_BPS = 10_000;

    /// @notice Role identifier for admin privileges
    uint256 public constant ADMIN_ROLE = _ROLE_0;

    /// @notice Role identifier for emergency admin privileges
    uint256 public constant EMERGENCY_ADMIN_ROLE = _ROLE_1;

    /// @notice Role identifier for oracle privileges
    uint256 public constant ORACLE_ROLE = _ROLE_2;

    /// @notice Role identifier for manager privileges
    uint256 public constant MANAGER_ROLE = _ROLE_3;

    /// @notice Role identifier for relayer privileges
    uint256 public constant RELAYER_ROLE = _ROLE_4;

    /// @notice Delay period for redeem requests
    uint24 public constant REQUEST_REDEEM_DELAY = 1 days;

    /// @notice Chain ID of the current network
    uint64 public immutable THIS_CHAIN_ID;

    /// @notice Number of supported chains
    uint256 public constant N_CHAINS = 7;

    /// @notice Array of destination chain IDs
    /// @dev Includes Ethereum Mainnet, Polygon, BNB Chain, Optimism, Base, Arbitrum One, and Avalanche
    uint64[N_CHAINS] public DST_CHAINS = [
        1, // Ethereum Mainnet
        137, // Polygon
        56, // BNB Chain
        10, // Optimism
        8453, // Base
        42_161, // Arbitrum One
        43_114 // Avalanche
    ];
    /// @notice Mapping of chain IDs to their respective indexes
    mapping(uint64 => uint256) chainIndexes;
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STORAGE                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // -- Slot 0
    /// @notice Cached value of total assets in this vault
    uint128 private _totalIdle;
    // -- Slot 1
    /// @notice Cached value of total allocated assets
    uint128 private _totalDebt;
    /// @notice Asset decimals
    uint8 _decimals;
    /// @notice Protocol fee
    uint16 public managementFee;
    /// @notice Protocol fee
    uint16 public oracleFee;
    /// @notice Minimum time users must wait to redeem shares
    uint24 public sharesLockTime;
    /// @notice Delay from processing a redeem till its claimed
    uint24 public processRedeemSettlement;
    /// @notice Wether the vault is paused
    bool public emergencyShutdown;
    // -- Slot  2
    /// @notice Fee receiver
    address public treasury;
    /// @notice Underlying asset
    address private immutable _asset;
    /// @notice Superform ERC1155 Superpositions
    ISuperPositions private immutable _superPositions;
    /// @notice Superform Router
    IBaseRouter private immutable _vaultRouter;
    /// @notice Superform Factory to validate superforms
    ISuperformFactory private immutable _factory;
    /// @notice ERC20 name
    string private _name;
    /// @notice ERC20 symbol
    string private _symbol;
    /// @notice maps the assets and data of each allocated vault
    mapping(uint256 => VaultData) public vaults;
    /// @notice the ERC4626 oracle of each chain
    mapping(uint64 chain => address) public oracles;
    /// @notice Vaults portfolio on this same chain
    uint256[WITHDRAWAL_QUEUE_SIZE] public localWithdrawalQueue;
    /// @notice Vaults portfolio in external chains
    uint256[WITHDRAWAL_QUEUE_SIZE] public xChainWithdrawalQueue;
    /// @notice Timestamp of deposit lock
    mapping(address => uint256) private _depositLockCheckPoint;
    /// @notice Receiver delegation for withdrawals
    mapping(address => address) private _receivers;
    /// @notice Implementation contract of the receiver contract
    address public receiverImplementation;
    /// @notice Timestamp of request redeem lock
    mapping(address => uint256) private _requestRedeemSettlementCheckpoint;
    /// @notice Inverse mapping vault => superformId
    mapping(address => uint256) _vaultToSuperformId;
    /// @notice Redeem is locked when requesting and unlocked when processing
    mapping(address => bool) redeemLocked;
    /// @notice Timestamp of last report
    uint256 public lastReport;
    /// @notice Signer address to process redeem requests
    address public signerRelayer;
    /// @notice pending bridged assets for each vault
    mapping(uint256 superformId => uint256 amount) private _pendingXChainDeposits;
    /// @notice Nonce of each controller
    mapping(address controller => uint256 nonce) private _controllerNonces;
    /// @notice Cached value of total assets that are being bridged at the moment
    uint256 private _totalPendingXChainDeposits;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           MODIFIERS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Modifier to prevent execution during emergency shutdown
    /// @dev Reverts the transaction if emergencyShutdown is true
    modifier noEmergencyShutdown() {
        if (emergencyShutdown) {
            revert VaultShutdown();
        }
        _;
    }

    /// @notice Initializes the MaxApyCrossChainVault contract
    /// @param _asset_ Address of the underlying asset token
    /// @param _name_ Name of the vault token
    /// @param _symbol_ Symbol of the vault token
    /// @param _managementFee Management fee in basis points
    /// @param _oracleFee Oracle fee in basis points
    /// @param _sharesLockTime Duration for which shares are locked after minting
    /// @param _processRedeemSettlement Time allowed for processing redeem settlements
    /// @param _superPositions_ Address of the SuperPositions contract
    /// @param _vaultRouter_ Address of the BaseRouter contract
    /// @param _factory_ Address of the SuperformFactory contract
    /// @param _treasury Address of the treasury to receive fees
    constructor(
        address _asset_,
        string memory _name_,
        string memory _symbol_,
        uint16 _managementFee,
        uint16 _oracleFee,
        uint24 _sharesLockTime,
        uint24 _processRedeemSettlement,
        ISuperPositions _superPositions_,
        IBaseRouter _vaultRouter_,
        ISuperformFactory _factory_,
        address _treasury,
        address _signerRelayer
    ) {
        _asset = _asset_;
        _name = _name_;
        _symbol = _symbol_;
        _factory = _factory_;
        _superPositions = _superPositions_;
        _vaultRouter = _vaultRouter_;
        treasury = _treasury;
        managementFee = _managementFee;
        oracleFee = _oracleFee;
        sharesLockTime = _sharesLockTime;
        processRedeemSettlement = _processRedeemSettlement;
        lastReport = block.timestamp;

        // Try to get asset decimals, fallback to default if unsuccessful
        (bool success, uint8 result) = _tryGetAssetDecimals(_asset_);
        _decimals = success ? result : _DEFAULT_UNDERLYING_DECIMALS;
        // Set the chain ID for the current network
        THIS_CHAIN_ID = uint64(block.chainid);
        // Initialize chainIndexes mapping
        for (uint256 i = 0; i != N_CHAINS; i++) {
            chainIndexes[DST_CHAINS[i]] = i;
        }
        // Approve vault router to spend the asset
        asset().safeApprove(address(_vaultRouter_), type(uint256).max);
        // Approve vault router to burn superpositions
        _superPositions_.setApprovalForAll(address(_vaultRouter_), true);

        // Initialize ownership and grant admin role
        _initializeOwner(msg.sender);
        _grantRoles(msg.sender, ADMIN_ROLE);

        signerRelayer = _signerRelayer;

        // Deploy and set the receiver implementation
        receiverImplementation = address(new ERC20Receiver(_asset_));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       PUBLIC GETTERS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns the name of the vault shares token.
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @notice Returns the symbol of the token.
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// @notice Returns the address of the underlying asset.
    function asset() public view override returns (address) {
        return _asset;
    }

    /// @notice Returns the total amount of the underlying asset managed by the Vault.
    function totalAssets() public view override returns (uint256 assets) {
        return _totalPendingXChainDeposits + totalWithdrawableAssets();
    }

    /// @notice Returns the total amount of the underlying assets that are settled.
    function totalWithdrawableAssets() public view returns (uint256 assets) {
        return totalLocalAssets() + totalXChainAssets();
    }

    /// @notice Returns the total amount of the underlying asset that are located on this
    /// same chain and can be transferred synchronously
    function totalLocalAssets() public view returns (uint256 assets) {
        assets = _totalIdle;
        for (uint256 i = 0; i != WITHDRAWAL_QUEUE_SIZE;) {
            VaultData memory vault = vaults[localWithdrawalQueue[i]];
            if (vault.vaultAddress == address(0)) break;
            assets += vault.convertToAssets(_sharesBalance(vault), false);
            ++i;
        }
        return assets;
    }

    /// @notice Returns the total amount of the underlying asset that are located on
    /// other chains and need asynchronous transfers
    function totalXChainAssets() public view returns (uint256 assets) {
        for (uint256 i = 0; i != WITHDRAWAL_QUEUE_SIZE;) {
            VaultData memory vault = vaults[xChainWithdrawalQueue[i]];
            if (vault.vaultAddress == address(0)) break;
            assets += vault.convertToAssets(_sharesBalance(vault), false);
            ++i;
        }
        return assets;
    }

    /// @notice Returns the estimate price of 1 vault share
    function sharePrice() public view returns (uint256) {
        return convertToAssets(10 ** decimals());
    }

    /// @notice returns the assets that are sitting idle in this contract
    /// @return assets amount of idle assets
    function totalIdle() public view returns (uint256 assets) {
        return _totalIdle;
    }

    /// @notice returns the total issued debt of underlying vaulrs
    /// @return assets amount assets that are invested in vaults
    function totalDebt() public view returns (uint256 assets) {
        return _totalDebt;
    }

    /// @notice helper function to see if a vault is listed
    function isVaultListed(address vaultAddress) public view returns (bool) {
        return _vaultToSuperformId[vaultAddress] != 0;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ERC7540 ACTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Transfers assets from sender into the Vault and submits a Request for asynchronous deposit.
    /// @param assets the amount of deposit assets to transfer from owner
    /// @param controller the controller of the request who will be able to operate the request
    /// @param owner the source of the deposit assets
    /// @return requestId
    function requestDeposit(
        uint256 assets,
        address controller,
        address owner
    )
        public
        override
        noEmergencyShutdown
        returns (uint256 requestId)
    {
        requestId = super.requestDeposit(assets, controller, owner);
        // fulfill the request directly
        _fulfillDepositRequest(controller, assets, convertToShares(assets));
    }

    /// @notice Mints shares Vault shares to receiver by claiming the Request of the controller.
    /// @dev uses msg.sender as controller
    /// @param shares to mint
    /// @param to shares receiver
    /// @return shares minted shares
    function deposit(uint256 assets, address to) public override returns (uint256 shares) {
        return deposit(assets, to, msg.sender);
    }

    /// @notice Mints shares Vault shares to receiver by claiming the Request of the controller.
    /// @param shares to mint
    /// @param to shares receiver
    /// @param controller controller address
    /// @return shares minted shares
    function deposit(
        uint256 assets,
        address to,
        address controller
    )
        public
        override
        noEmergencyShutdown
        returns (uint256 shares)
    {
        uint256 sharesBalance = balanceOf(to);
        shares = super.deposit(assets, to, controller);
        // Start shares lock time
        _lockShares(to, sharesBalance, shares);
        _afterDeposit(assets, shares);
    }

    /// @notice Mints exactly shares Vault shares to receiver by claiming the Request of the controller.
    /// @dev uses msg.sender as controllerisValidSignat
    /// @param shares to mint
    /// @param to shares receiver
    /// @return assets deposited assets
    function mint(uint256 shares, address to) public override returns (uint256 assets) {
        return mint(shares, to, msg.sender);
    }

    /// @notice Mints exactly shares Vault shares to receiver by claiming the Request of the controller.
    /// @param shares to mint
    /// @param to shares receiver
    /// @param controller controller address
    /// @return assets deposited assets
    function mint(
        uint256 shares,
        address to,
        address controller
    )
        public
        override
        noEmergencyShutdown
        returns (uint256 assets)
    {
        uint256 sharesBalance = balanceOf(to);
        assets = super.mint(shares, to, controller);
        _lockShares(to, sharesBalance, shares);
        _afterDeposit(assets, shares);
    }

    /// @notice Assumes control of shares from sender into the Vault and submits a Request for asynchronous redeem.
    /// @param shares the amount of shares to be redeemed to transfer from owner
    /// @param controller the controller of the request who will be able to operate the request
    /// @param owner the source of the shares to be redeemed
    /// @return requestId id
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    )
        public
        override
        returns (uint256 requestId)
    {
        // Require deposited shares arent locked
        _checkSharesLocked(controller);
        requestId = super.requestRedeem(shares, controller, owner);
        // Lock redeem till the request is processed
        redeemLocked[controller] = true;
    }
    /// @dev Redeems shares for assets, ensuring all settled requests are fulfilled
    /// @param shares The number of shares to redeem
    /// @param receiver The address that will receive the assets
    /// @param controller The address that controls the redemption
    /// @return assets The amount of assets redeemed

    function redeem(
        uint256 shares,
        address receiver,
        address controller
    )
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        _checkRedeemProcessed(controller);
        // Require a settlement from the last redem request
        _checkRequestsSettled(controller);
        // Fulfill the request if theres any pending assets
        _fulfillSettledRequests(controller);
        return super.redeem(shares, receiver, controller);
    }

    /// @dev Withdraws assets, ensuring all settled requests are fulfilled
    /// @param assets The amount of assets to withdraw
    /// @param receiver The address that will receive the assets
    /// @param controller The address that controls the withdrawal
    /// @return shares The number of shares burned
    function withdraw(
        uint256 assets,
        address receiver,
        address controller
    )
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        // Require a settlement from the last redem request
        _checkRequestsSettled(controller);
        // Fulfill the request if theres any pending assets
        _fulfillSettledRequests(controller);
        return super.withdraw(assets, receiver, controller);
    }

    // function redeemAtomic(uint256 shares, address controller, address owner, address receiver) public nonReentrant {
    //     _checkSharesLocked(controller);
    //     _processRedeemRequest(shares, controller, owner, receiver, false);
    // }

    /// @notice Processes a redemption request for a given controller
    /// @dev This function is restricted to the RELAYER_ROLE and handles asynchronous processing of redemption requests,
    /// including cross-chain withdrawals
    /// @param controller The address of the controller initiating the redemption
    function processRedeemRequest(
        address controller,
        SingleXChainSingleVaultWithdraw calldata sXsV,
        SingleXChainMultiVaultWithdraw calldata sXmV,
        MultiXChainSingleVaultWithdraw calldata mXsV,
        MultiXChainMultiVaultWithdraw calldata mXmV
    )
        external
        payable
        onlyRoles(RELAYER_ROLE)
    {
        // Retrieve the pending redeem request for the specified controller
        // This request may involve cross-chain withdrawals from various ERC4626 vaults

        // Process the redemption request asynchronously
        // Parameters:
        // 1. pendingRedeemRequest(controller): Fetches the pending shares
        // 2. controller: The address initiating the redemption (used as both 'from' and 'to')
        // 3. address(this): The vault itself as the receiver of the redeemed assets
        // 4. true: Retain the assets, dont send them directly to the controller
        _processRedeemRequest(
            ProcessRedeemRequestConfig(
                pendingRedeemRequest(controller), controller, controller, address(this), true, sXsV, sXmV, mXsV, mXmV
            )
        );
        // Note: After processing, the redeemed assets are held by this contract
        // The user can later claim these assets using `redeem` or `withdraw`
    }

    struct ProcessRedeemRequestWithSignatureParams {
        address controller;
        SingleXChainSingleVaultWithdraw sXsV;
        SingleXChainMultiVaultWithdraw sXmV;
        MultiXChainSingleVaultWithdraw mXsV;
        MultiXChainMultiVaultWithdraw mXmV;
        bytes signature;
    }

   
    function processRedeemRequestWithSignature(ProcessRedeemRequestWithSignatureParams calldata params)
        external
        payable
    {
        bytes32 hash;
        {
            hash = keccak256(abi.encode(
                ++_controllerNonces[params.controller],
                params.controller,
                keccak256(abi.encode(params.sXsV)), 
                keccak256(abi.encode(params.sXmV)), 
                keccak256(abi.encode(params.mXsV)), 
                keccak256(abi.encode(params.mXmV))
            ))          ;
        }
        // Needs explicit approval from the relayer
        _checkSignerIsRelayer(
            params.controller, hash, params.signature
        );

        // Retrieve the pending redeem request for the specified controller
        // This request may involve cross-chain withdrawals from various ERC4626 vaults

        // Process the redemption request asynchronously
        // Parameters:
        // 1. pendingRedeemRequest(controller): Fetches the pending shares
        // 2. controller: The address initiating the redemption (used as both 'from' and 'to')
        // 3. address(this): The vault itself as the receiver of the redeemed assets
        // 4. true: Retain the assets, dont send them directly to the controller
        _processRedeemRequest(
            ProcessRedeemRequestConfig(
                pendingRedeemRequest(params.controller),
                params.controller,
                params.controller,
                address(this),
                true,
                params.sXsV,
                params.sXmV,
                params.mXsV,
                params.mXmV
            )
        );
        // Note: After processing, the redeemed assets are held by this contract
        // The user can later claim these assets using `redeem` or `withdraw`
    }

    function _checkSignerIsRelayer(
        address controller,
        bytes32 hash,
        bytes memory signature
    )
        private
    {

        if (!SignatureCheckerLib.isValidSignatureNow(signerRelayer, hash, signature)) {
            revert();
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VAULT MANAGEMENT                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function previewWithdrawalRoute(uint256 assets)
        public
        view
        returns (ProcessRedeemRequestCache memory cachedRoute)
    {
        cachedRoute.assets = assets;
        uint256 shares = convertToShares(assets);
        cachedRoute.totalIdle = _totalIdle;
        cachedRoute.totalDebt = _totalDebt;
        cachedRoute.totalAssets = totalAssets();

        // Cannot process more assets than the available
        if (cachedRoute.assets > cachedRoute.totalAssets - _totalPendingXChainDeposits) {
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

    /// @notice Invests assets from this vault into a single target vault within the same chain
    /// @dev Only callable by addresses with the MANAGER_ROLE
    /// @param vaultAddress The address of the target vault to invest in
    /// @param amount The amount of assets to invest
    /// @param minAmountOut The minimum amount of shares expected to receive from the investment
    /// @return shares The number of shares received from the target vault
    function investSingleDirectSingleVault(
        address vaultAddress,
        uint256 amount,
        uint256 minAmountOut
    )
        public
        onlyRoles(MANAGER_ROLE)
        returns (uint256 shares)
    {
        // Ensure the target vault is in the approved list
        if (!isVaultListed(vaultAddress)) revert VaultNotListed();

        // Record the balance before deposit to calculate received shares
        uint256 balanceBefore = vaultAddress.balanceOf(address(this));

        // Deposit assets into the target vault
        ERC4626(vaultAddress).deposit(amount, address(this));

        // Calculate the number of shares received
        shares = vaultAddress.balanceOf(address(this)) - balanceBefore;

        // Ensure the received shares meet the minimum expected amount
        if (shares < minAmountOut) {
            revert InsufficientAssets();
        }

        // Update the vault's internal accounting
        uint128 amountUint128 = amount.toUint128();
        _totalIdle -= amountUint128;
        _totalDebt += amountUint128;
        vaults[_vaultToSuperformId[vaultAddress]].totalDebt += amountUint128;

        emit Invest(amount);
        return shares;
    }

    /// @notice Invests assets from this vault into multiple target vaults within the same chain
    /// @dev Calls investSingleDirectSingleVault for each target vault
    /// @param vaultAddresses An array of addresses of the target vaults to invest in
    /// @param amounts An array of amounts to invest in each corresponding vault
    /// @param minAmountOuts An array of minimum amounts of shares expected from each investment
    /// @return shares An array of the number of shares received from each target vault
    function investSingleDirectMultiVault(
        address[] calldata vaultAddresses,
        uint256[] calldata amounts,
        uint256[] calldata minAmountOuts
    )
        external
        returns (uint256[] memory shares)
    {
        shares = new uint256[](vaultAddresses.length);
        for (uint256 i = 0; i < vaultAddresses.length; ++i) {
            shares[i] = investSingleDirectSingleVault(vaultAddresses[i], amounts[i], minAmountOuts[i]);
        }
    }

    /// @notice Invests assets from this vault into a single target vault on a different chain
    /// @dev Only callable by addresses with the MANAGER_ROLE
    /// @param superformId The identifier of the target vault in the Superform system
    /// @param ambIds An array of AMB (Asset Management Bridge) identifiers for cross-chain communication
    /// @param amount The amount of assets to invest
    /// @param outputAmount The expected amount of shares to receive
    /// @param maxSlippage The maximum acceptable slippage for the cross-chain transaction
    /// @param liqRequest Liquidity request parameters for the cross-chain transaction
    /// @param hasDstSwap Boolean indicating if a swap is needed on the destination chain
    function investSingleXChainSingleVault(
        uint256 superformId,
        uint8[] memory ambIds,
        uint256 amount,
        uint256 outputAmount,
        uint256 maxSlippage,
        LiqRequest memory liqRequest,
        bool hasDstSwap
    )
        public
        payable
        onlyRoles(MANAGER_ROLE)
    {
        // Retrieve the vault data for the target vault
        VaultData memory vault = vaults[superformId];

        // Cant invest in a vault that is not in the portfolio
        if (!isVaultListed(vault.vaultAddress)) revert VaultNotListed();

        // We cannot invest more till the previous investment is successfully completed
        if (_pendingXChainDeposits[superformId] != 0) revert XChainDepositsPending();

        // Prepare the cross-chain deposit request
        SingleXChainSingleVaultStateReq memory req = SingleXChainSingleVaultStateReq({
            ambIds: ambIds,
            dstChainId: vault.chainId,
            superformData: SingleVaultSFData({
                superformId: superformId,
                amount: amount,
                outputAmount: outputAmount,
                maxSlippage: maxSlippage,
                liqRequest: liqRequest,
                permit2data: "",
                hasDstSwap: hasDstSwap,
                retain4626: false,
                receiverAddress: address(this),
                receiverAddressSP: address(this),
                extraFormData: ""
            })
        });

        // Initiate the cross-chain deposit via the vault router
        _vaultRouter.singleXChainSingleVaultDeposit{ value: msg.value }(req);

        // Update the vault's internal accounting
        uint128 amountUint128 = amount.toUint128();
        _totalIdle -= amountUint128;
        // Account assets as pending
        _pendingXChainDeposits[superformId] = amount;
        _totalPendingXChainDeposits += amount;
        emit Invest(amount);
    }

    /// @notice Placeholder for investing in multiple vaults across chains
    /// @dev Not implemented yet
    function investSingleXChainMultiVault(
        uint256[] calldata superformIds,
        uint8[][] memory ambIds,
        uint256[] calldata amounts,
        uint256[] calldata outputAmounts,
        uint256[] calldata maxSlippages,
        LiqRequest[] memory liqRequests,
        bool[] calldata hasDstSwaps
    )
        external
    {
        uint256 totalAmount;
        for (uint256 i = 0; i < superformIds.length; ++i) {
            investSingleXChainSingleVault(
                superformIds[i],
                ambIds[i],
                amounts[i],
                outputAmounts[i],
                maxSlippages[i],
                liqRequests[i],
                hasDstSwaps[i]
            );
            totalAmount += amounts[i];
        }
        emit Invest(totalAmount);
    }

    /// @notice Placeholder for investing multiple assets in a single vault across chains
    /// @dev Not implemented yet
    function investMultiXChainSingleVault() external onlyRoles(MANAGER_ROLE) { }

    /// @notice Placeholder for investing multiple assets in multiple vaults across chains
    /// @dev Not implemented yet
    function investMultiXChainMultiVault() external onlyRoles(MANAGER_ROLE) { }

    /// @notice Updates the share prices of vaults based on oracle reports
    /// @dev This function can only be called by addresses with the ORACLE_ROLE
    /// @param reports An array of VaultReport structures containing updated share prices
    /// @param source The address of the oracle providing the report
    function report(VaultReport[] calldata reports, address source) external onlyRoles(ORACLE_ROLE) {
        int256 totalAssetsDelta;

        for (uint256 i = 0; i < reports.length; i++) {
            // Cache the current report for efficiency
            VaultReport memory _report = reports[i];

            // Ensure the reported vault is in the approved list
            if (!isVaultListed(_report.vaultAddress)) revert VaultNotListed();

            // Retrieve the superform ID for the vault
            uint256 superformId = _vaultToSuperformId[_report.vaultAddress];

            // Cache the vault data for easier access
            VaultData memory vault = vaults[superformId];

            // Get the current balance of vault shares
            uint256 sharesBalance = _sharesBalance(vault);

            // Calculate the total assets value before applying the new share price
            uint256 totalAssetsBefore = vault.convertToAssetsCachedSharePrice(sharesBalance);

            // Update the vault's share price with the new reported value
            vaults[superformId].lastReportedSharePrice = _report.sharePrice;

            // Calculate the total assets value after applying the new share price
            uint256 totalAssetsAfter = vault.convertToAssets(sharesBalance, true);

            // Calculate the change in total assets (profit or loss)
            totalAssetsDelta += int256(totalAssetsAfter) - int256(totalAssetsBefore);

            emit Report(vault.chainId, vault.vaultAddress, totalAssetsDelta);
        }

        // Calculate and distribute management fees based on the change in total assets
        _assessFees(treasury, source);
    }

    /// @notice Add a new vault to the portfolio
    /// @param chainId chainId of the vault
    /// @param superformId id of superform in case its crosschain
    /// @param vault vault address
    /// @param vaultDecimals decimals of ERC4626 token
    /// @param oracle vault shares price oracle
    function addVault(
        uint64 chainId,
        uint256 superformId,
        address vault,
        uint8 vaultDecimals,
        IERC4626Oracle oracle
    )
        external
        onlyRoles(ADMIN_ROLE)
    {
        if (superformId == 0) revert();
        // If its already listed revert
        if (isVaultListed(vault)) revert VaultAlreadyListed();

        // Save it into storage
        vaults[superformId].chainId = chainId;
        vaults[superformId].superformId = superformId;
        vaults[superformId].vaultAddress = vault;
        vaults[superformId].decimals = vaultDecimals;
        vaults[superformId].oracle = oracle;
        uint192 lastSharePrice = uint192(vaults[superformId].sharePrice());
        if (lastSharePrice == 0) revert();
        vaults[superformId].lastReportedSharePrice = lastSharePrice;
        _vaultToSuperformId[vault] = superformId;

        if (chainId == THIS_CHAIN_ID) {
            // Push it to the local withdrawal queue
            uint256[WITHDRAWAL_QUEUE_SIZE] memory queue = localWithdrawalQueue;
            for (uint256 i = 0; i != WITHDRAWAL_QUEUE_SIZE; i++) {
                if (queue[i] == 0) {
                    localWithdrawalQueue[i] = superformId;
                    break;
                }
            }
            // If its on the same chain perfom approval to vault
            asset().safeApprove(vault, type(uint256).max);
        } else {
            // Push it to the crosschain withdrawal queue
            uint256[WITHDRAWAL_QUEUE_SIZE] memory queue = xChainWithdrawalQueue;
            for (uint256 i = 0; i != WITHDRAWAL_QUEUE_SIZE; i++) {
                if (queue[i] == 0) {
                    xChainWithdrawalQueue[i] = superformId;
                    break;
                }
            }
        }

        emit AddVault(chainId, vault);
    }

    /// @notice Sets the emergency shutdown state of the vault
    /// @dev Can only be called by addresses with the EMERGENCY_ADMIN_ROLE
    /// @param _emergencyShutdown True to enable emergency shutdown, false to disable
    function setEmergencyShutdown(bool _emergencyShutdown) external onlyRoles(EMERGENCY_ADMIN_ROLE) {
        emergencyShutdown = _emergencyShutdown;
        emit EmergencyShutdown(_emergencyShutdown);
    }

    /// @notice set the oracle for one chain
    /// @param chainId the oracle
    /// @param oracle for that chain
    function setOracle(uint64 chainId, address oracle) external onlyRoles(ADMIN_ROLE) {
        oracles[chainId] = oracle;
        emit SetOracle(chainId, oracle);
    }

    function setSharesLockTime(uint24 time) external onlyRoles(ADMIN_ROLE) {
        sharesLockTime = time;
        emit SetSharesLockTime(time);
    }

    /// @notice sets the annually management fee
    /// @param _managementFee new BPS management fee
    function setManagementFee(uint16 _managementFee) external onlyRoles(ADMIN_ROLE) {
        managementFee = _managementFee;
        emit SetManagementFee(_managementFee);
    }

    /// @notice sets the annually oracle fee
    /// @param _oracleFee new BPS oracle fee
    function setOracleFee(uint16 _oracleFee) external onlyRoles(ADMIN_ROLE) {
        oracleFee = _oracleFee;
        emit SetOracleFee(_oracleFee);
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

    function _exhaustWithdrawalQueue(
        ProcessRedeemRequestCache memory cache,
        uint256[WITHDRAWAL_QUEUE_SIZE] memory queue,
        bool resetValues
    )
        private
        view
    {
        if (resetValues) {
            console2.log("------xchain queue----");
        } else {
            console2.log("------local queue----");
        }
        console2.log("amountToWithdraw : ", cache.amountToWithdraw);
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
            uint256 maxWithdraw = vault.convertToAssets(_sharesBalance(vault), true);
            console2.log("maxWithdraw : ", maxWithdraw);
            console2.log("need : ", cache.amountToWithdraw);

            // Dont withdraw more than max
            uint256 withdrawAssets = Math.min(maxWithdraw, cache.amountToWithdraw);
            if (withdrawAssets == 0) continue;
            // Cache chain index
            uint256 chainIndex = chainIndexes[vault.chainId];
            // Cache chain length
            uint256 len = cache.lens[chainIndex];
            // Push the superformId to the last index of the array
            cache.dstVaults[chainIndex][len] = vault.superformId;
            uint256 shares = vault.convertToShares(withdrawAssets, true);
            console2.log("4626 balance : ", _superPositions.balanceOf(address(this), vault.superformId));
            console2.log("4626 shares : ", shares);
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

        if (resetValues) {
            console2.log("------xchain queue----");
        } else {
            console2.log("------local queue----");
        }
    }

    /// @param shares to redeem and burn
    /// @param controller controller that created the request
    /// @param owner shares owner
    /// @param receiver address of the assets receiver in case its a
    /// @param retainAssets true if the transaction is atomic
    struct ProcessRedeemRequestConfig {
        uint256 shares;
        address controller;
        address owner;
        address receiver;
        bool retainAssets;
        SingleXChainSingleVaultWithdraw sXsV;
        SingleXChainMultiVaultWithdraw sXmV;
        MultiXChainSingleVaultWithdraw mXsV;
        MultiXChainMultiVaultWithdraw mXmV;
    }

    /// @notice Executes the redeem request for a controller
    function _processRedeemRequest(ProcessRedeemRequestConfig memory config) private {
        console2.log("shares : ", config.shares);
        // Use struct to avoid stack too deep
        ProcessRedeemRequestCache memory cache;
        cache.totalIdle = _totalIdle;
        cache.totalDebt = _totalDebt;
        cache.assets = convertToAssets(config.shares);
        cache.totalAssets = totalAssets();
        bool settle;

        // Cannot process more assets than the
        if (cache.assets > cache.totalAssets - _totalPendingXChainDeposits) {
            revert InsufficientAvailableAssets();
        }

        // If totalIdle can covers the amount fulfill directly
        if (cache.totalIdle >= cache.assets) {
            console2.log("here wrong");
            cache.sharesFulfilled = config.shares;
            cache.totalClaimableWithdraw = cache.assets;
        }
        // Otherwise perform Superform withdrawals
        else {
            console2.log("totalIdle : ", cache.totalIdle);
            // Cache amount to withdraw before reducing totalIdle
            cache.amountToWithdraw = cache.assets - cache.totalIdle;
            console2.log("amountToWithdraw : ", cache.amountToWithdraw);

            // Use totalIdle to fulfill the request
            if (cache.totalIdle > 0) {
                cache.totalClaimableWithdraw = cache.totalIdle;
                cache.sharesFulfilled = _convertToShares(cache.totalIdle, cache.totalAssets);
            }
            ///////////////////////////////// PREVIOUS CALCULATIONS ////////////////////////////////
            console2.log("-----prepare-----");
            _prepareWithdrawalRoute(cache);
            console2.log("-----prepare-----");
            //////////////////////////////// WITHDRAW FROM THIS CHAIN ////////////////////////////////
            // Cache chain index
            uint256 chainIndex = chainIndexes[THIS_CHAIN_ID];
            if (cache.lens[chainIndex] > 0) {
                address directWithdrawalReceiver = config.retainAssets ? address(this) : config.receiver;
                if (cache.lens[chainIndex] == 1) {
                    // shares to redeem
                    uint256 sharesAmount = cache.sharesPerVault[chainIndex][0];
                    console2.log("4626 shares direct: ", sharesAmount);
                    // assets to withdraw
                    uint256 assetsAmount = cache.assetsPerVault[chainIndex][0];
                    // superformId(take first element fo the array)
                    uint256 superformId = cache.dstVaults[chainIndex][0];
                    // get actual withdrawn amount
                    uint256 withdrawn = _singleDirectSingleVaultWithdraw(
                        vaults[superformId].vaultAddress, sharesAmount, 0, directWithdrawalReceiver
                    );
                    // cache shares to burn
                    cache.sharesFulfilled += _convertToShares(assetsAmount, cache.totalAssets);
                    // reduce vault debt
                    vaults[superformId].totalDebt =
                        _sub0(vaults[superformId].totalDebt, cache.assetsPerVault[chainIndex][0]).toUint128();
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
                    uint256 withdrawn = _singleDirectMultiVaultWithdraw(
                        vaultAddresses, amounts, _getEmptyUint256Array(amounts.length), directWithdrawalReceiver
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

                    for (uint256 i = 0; i < N_CHAINS; ++i) {
                        if (DST_CHAINS[i] == THIS_CHAIN_ID) continue;
                        // The vaults list length should be 1(single-vault)
                        if (cache.lens[i] > 0) {
                            chainId = DST_CHAINS[i];
                            superformId = cache.dstVaults[i][0];
                            amount = cache.sharesPerVault[i][0];
                            console2.log("4626 shares xchain: ", amount);

                            // Withdraw from one vault asynchronously(crosschain)
                            _singleXChainSingleVaultWithdraw(chainId, superformId, amount, config.receiver, config.sXsV);
                            // reduce vault debt
                            vaults[superformId].totalDebt =
                                _sub0(vaults[superformId].totalDebt, cache.assetsPerVault[chainIndex][0]).toUint128();
                            settle = true;
                            break;
                        }
                    }
                } else {
                    uint256[] memory superformIds;
                    uint256[] memory amounts;
                    uint64 chainId;

                    for (uint256 i = 0; i < cache.dstVaults.length; ++i) {
                        if (DST_CHAINS[i] == THIS_CHAIN_ID) continue;
                        if (cache.lens[i] > 0) {
                            chainId = DST_CHAINS[i];
                            superformIds = _toDynamicUint256Array(cache.dstVaults[i], cache.lens[i]);
                            amounts = _toDynamicUint256Array(cache.sharesPerVault[i], cache.lens[i]);
                            // Withdraw from multiple vaults asynchronously(crosschain)
                            _singleXChainMultiVaultWithdraw(
                                chainId, superformIds, amounts, config.receiver, config.sXmV
                            );
                            // reduce vault debt
                            // vaults[cache.dstVaults[i]].totalDebt =
                            //    _sub0(vaults[cache.dstVaults[i]].totalDebt,cache.assetsPerVault[chainIndex][i]).toUint128();
                            settle = true;
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

                    for (uint256 i = 0; i < chainsLen; i++) {
                        singleVaultDatas[i] = SingleVaultSFData({
                            superformId: cache.dstVaults[i][0],
                            amount: cache.sharesPerVault[i][0],
                            outputAmount: config.mXsV.outputAmounts[i],
                            maxSlippage: config.mXsV.maxSlippages[i],
                            liqRequest: config.mXsV.liqRequests[i],
                            permit2data: _getEmptyBytes(),
                            hasDstSwap: config.mXsV.hasDstSwaps[i],
                            retain4626: false,
                            receiverAddress: config.receiver,
                            receiverAddressSP: address(0),
                            extraFormData: _getEmptyBytes()
                        });
                        ambIds[i] = config.mXsV.ambIds[i];
                    }
                    _multiDstSingleVaultWithdraw(ambIds, dstChainIds, singleVaultDatas, config.mXsV.value);
                    settle = true;
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

                    for (uint256 i = 0; i < chainsLen; i++) {
                        uint256[] memory emptyUint256Array = _getEmptyUint256Array(cache.lens[i]);
                        bool[] memory emptyBoolArray = _getEmptyBoolArray(cache.lens[i]);
                        multiVaultDatas[i] = MultiVaultSFData({
                            superformIds: _toDynamicUint256Array(cache.dstVaults[i], cache.lens[i]),
                            amounts: _toDynamicUint256Array(cache.sharesPerVault[i], cache.lens[i]),
                            outputAmounts: config.mXmV.outputAmounts[i],
                            maxSlippages: config.mXmV.maxSlippages[i],
                            liqRequests: config.mXmV.liqRequests[i],
                            permit2data: _getEmptyBytes(),
                            hasDstSwaps: config.mXmV.hasDstSwaps[i],
                            retain4626s: emptyBoolArray,
                            receiverAddress: config.receiver,
                            receiverAddressSP: address(0),
                            extraFormData: _getEmptyBytes()
                        });
                        ambIds[i] = config.mXmV.ambIds[i];
                    }
                    // Withdraw from multiple vaults and chains asynchronously
                    _multiDstMultiVaultWithdraw(ambIds, dstChainIds, multiVaultDatas, config.mXmV.value);
                    settle = true;
                }
            }
        }

        // If there's any crosschain redeem going on start settlement
        if (settle) {
            _requestRedeemSettlementCheckpoint[config.controller] = block.timestamp;
        } else {
            // Adjust so no dust is left
            cache.sharesFulfilled = config.shares;
        }

        // Unlock redeem
        redeemLocked[config.controller] = false;

        // Optimistically deduct all assets to withdraw from the total
        _totalIdle = cache.totalIdle.toUint128();
        _totalIdle -= cache.totalClaimableWithdraw.toUint128();
        _totalDebt = cache.totalDebt.toUint128();

        emit ProcessRedeemRequest(config.controller, config.shares);

        // In case its not atommic
        if (config.retainAssets) {
            // Burn all shares from this contract(they already have been transferred)
            _burn(address(this), config.shares);
            // Fulfill request with instant withdrawals only
            _fulfillRedeemRequest(cache.sharesFulfilled, cache.totalClaimableWithdraw, config.controller);
        }
        // If atomic
        else {
            // Burn all shares from owner
            _burn(config.owner, config.shares);
            // Transfer instant withdrawal to receiver
            asset().safeTransfer(config.receiver, cache.totalClaimableWithdraw);
        }
    }

    /// @notice fulfills the already settled redeem requests
    /// @param controller controller address
    function _fulfillSettledRequests(address controller) private {
        ERC20Receiver receiverContract = ERC20Receiver(_receiver(controller));
        uint256 claimableXChain = receiverContract.balance();
        receiverContract.pull(claimableXChain);
        uint256 shares = pendingRedeemRequest(controller);
        _fulfillRedeemRequest(shares, claimableXChain, controller);
        emit FulfillRedeemRequest(controller, shares, claimableXChain);
    }

    /// @notice the number of decimals of the underlying token
    function _underlyingDecimals() internal view override returns (uint8) {
        return _decimals;
    }

    /// @notice Applies annualized fees to vault assets
    /// @notice Mints shares to the treasury
    function _assessFees(address managementFeeReceiver, address oracleFeeReceiver) private {
        uint256 duration = block.timestamp - lastReport;

        uint256 managementFees = (totalAssets() * duration * managementFee) / SECS_PER_YEAR / MAX_BPS;
        uint256 managementFeeShares = convertToShares(managementFees);

        uint256 oracleFees = (totalAssets() * duration * oracleFee) / SECS_PER_YEAR / MAX_BPS;
        uint256 oracleFeeShares = convertToShares(oracleFees);
        _mint(managementFeeReceiver, managementFeeShares);
        _mint(oracleFeeReceiver, oracleFeeShares);
    }

    /// @dev Hook that is called after any deposit or mint.
    function _afterDeposit(uint256 assets, uint256 /*uint256 shares*/ ) internal override {
        uint128 assetsUint128 = assets.toUint128();
        _totalIdle += assetsUint128;
    }

    function _checkRequestsSettled(address controller) private view {
        if (block.timestamp < _requestRedeemSettlementCheckpoint[controller] + processRedeemSettlement) {
            revert RequestNotSettled();
        }
    }

    function _checkRedeemProcessed(address controller) private view {
        if (redeemLocked[controller]) {
            revert RedeemNotProcessed();
        }
    }

    /// @dev Reverts if deposited shares are locked
    /// @param controller shares controller
    function _checkSharesLocked(address controller) private view {
        if (block.timestamp < _depositLockCheckPoint[controller] + sharesLockTime) revert SharesLocked();
    }

    /// @dev Locks the deposited shares for a fixed period
    /// @param to shares receiver
    /// @param sharesBalance current shares balance
    /// @param newShares newly minted shares
    function _lockShares(address to, uint256 sharesBalance, uint256 newShares) private {
        uint256 newBalance = sharesBalance + newShares;
        if (sharesBalance == 0) {
            _depositLockCheckPoint[to] = block.timestamp;
        } else {
            _depositLockCheckPoint[to] = ((_depositLockCheckPoint[to] * sharesBalance) / newBalance)
                + ((block.timestamp * newShares) / newBalance);
        }
    }

    /// @dev Helper function to get a empty bytes
    function _getEmptyBytes() private pure returns (bytes memory) {
        return new bytes(0);
    }

    /// @dev Private helper to substract a - b or return 0 if it underflows
    function _sub0(uint256 a, uint256 b) private pure returns (uint256) {
        unchecked {
            return a - b > a ? 0 : a - b;
        }
    }

    /// @dev Private helper get an array uint256 full of zeros
    /// @param len array length
    /// @return
    function _getEmptyUint256Array(uint256 len) private pure returns (uint256[] memory) {
        return new uint256[](len);
    }

    /// @dev Helper function to get a empty bools array
    function _getEmptyBoolArray(uint256 len) private pure returns (bool[] memory) {
        return new bool[](len);
    }

    /// @dev Withdraws assets from a single vault on the same chain
    /// @param vault Address of the vault to withdraw from
    /// @param amount Amount of shares to redeem
    /// @param minAmountOut Minimum amount of assets expected to receive
    /// @param receiver Address to receive the withdrawn assets
    /// @return withdrawn Amount of assets actually withdrawn
    function _singleDirectSingleVaultWithdraw(
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
    /// @param vaults Array of vault addresses to withdraw from
    /// @param amounts Array of share amounts to redeem from each vault
    /// @param minAmountsOut Array of minimum amounts of assets expected from each vault
    /// @param receiver Address to receive the withdrawn assets
    /// @return withdrawn Total amount of assets withdrawn from all vaults
    function _singleDirectMultiVaultWithdraw(
        address[] memory vaults,
        uint256[] memory amounts,
        uint256[] memory minAmountsOut,
        address receiver
    )
        private
        returns (uint256 withdrawn)
    {
        for (uint256 i = 0; i < vaults.length; ++i) {
            withdrawn += _singleDirectSingleVaultWithdraw(vaults[i], amounts[i], minAmountsOut[i], receiver);
        }
    }

    /// @dev Initiates a withdrawal from a single vault on a different chain
    /// @param chainId ID of the destination chain
    /// @param superformId ID of the superform to withdraw from
    /// @param amount Amount of shares to withdraw
    /// @param receiver Address to receive the withdrawn assets
    /// @param config Configuration for the cross-chain withdrawal
    function _singleXChainSingleVaultWithdraw(
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
    function _singleXChainMultiVaultWithdraw(
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
    function _multiDstSingleVaultWithdraw(
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
    function _multiDstMultiVaultWithdraw(
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

    /// @dev Helper function to convert a fixed array to dynamic
    /// @param arr fixed uint256 array
    /// @param len length of new dynamic array
    /// @return dynArr new dynamic array
    function _toDynamicUint256Array(
        uint256[WITHDRAWAL_QUEUE_SIZE] memory arr,
        uint256 len
    )
        private
        pure
        returns (uint256[] memory dynArr)
    {
        dynArr = new uint256[](len);
        for (uint256 i = 0; i < len; ++i) {
            dynArr[i] = arr[i];
        }
    }

    /// @dev Returns the delegatee of a owner to receive the assets
    /// @dev If it doesnt exist it deploys it at the moment
    /// @notice receiverAddress returns delegatee
    function _receiver(address controller) private returns (address receiverAddress) {
        address current = _receivers[controller];
        if (current != address(0)) {
            return current;
        } else {
            receiverAddress =
                LibClone.clone(receiverImplementation, abi.encodeWithSignature("initialize(address)", controller));
            _receivers[controller] = receiverAddress;
        }
    }

    /// @dev Gets the shares balance of a vault in the porfolio
    /// @dev If its on the same chain we fetch it from the vault directly,
    /// otherwise from the Superform ERC1155 Superpositions
    ///
    /// @return shares shares balance
    function _sharesBalance(VaultData memory data) private view returns (uint256 shares) {
        if (data.chainId == THIS_CHAIN_ID) {
            return ERC4626(data.vaultAddress).balanceOf(address(this));
        } else {
            return _superPositions.balanceOf(address(this), data.superformId);
        }
    }

    /// @dev Private helper to return `x + 1` without the overflow check.
    /// Used for computing the denominator input to `FixedPointMathLib.fullMulDiv(a, b, x + 1)`.
    /// When `x == type(uint256).max`, we get `x + 1 == 0` (mod 2**256 - 1),
    /// and `FixedPointMathLib.fullMulDiv` will revert as the denominator is zero.
    function _inc_(uint256 x) private pure returns (uint256) {
        unchecked {
            return x + 1;
        }
    }

    /// @dev Private helper to return if either value is zero.
    function _eitherIsZero_(uint256 a, uint256 b) private pure returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := or(iszero(a), iszero(b))
        }
    }

    /// @dev Private helper to calculate shares from any @param _totalAssets
    function _convertToShares(uint256 assets, uint256 _totalAssets) private view returns (uint256 shares) {
        if (!_useVirtualShares()) {
            uint256 supply = totalSupply();
            return _eitherIsZero_(assets, supply)
                ? _initialConvertToShares(assets)
                : Math.fullMulDiv(assets, supply, _totalAssets);
        }
        uint256 o = _decimalsOffset();
        if (o == uint256(0)) {
            return Math.fullMulDiv(assets, totalSupply() + 1, _inc_(_totalAssets));
        }
        return Math.fullMulDiv(assets, totalSupply() + 10 ** o, _inc_(_totalAssets));
    }

    /// @dev Supports ERC1155 interface detection
    /// @param interfaceId The interface identifier, as specified in ERC-165
    /// @return bool True if the contract supports the interface, false otherwise
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        if (interfaceId == 0x4e2312e0) return true;
    }

    /// @notice Handles the receipt of a single ERC1155 token type
    /// @dev This function is called at the end of a `safeTransferFrom` after the balance has been updated
    /// @param operator The address which initiated the transfer (i.e. msg.sender)
    /// @param from The address which previously owned the token
    /// @param superformId The ID of the token being transferred
    /// @param value The amount of tokens being transferred
    /// @param data Additional data with no specified format
    /// @return bytes4 `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
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
        uint256 bridgedAssets = _pendingXChainDeposits[superformId];
        delete _pendingXChainDeposits[superformId];
        _totalPendingXChainDeposits -= bridgedAssets;
        emit SettleXChainInvest(superformId, bridgedAssets);
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
    /// @return bytes4 `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
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
}
