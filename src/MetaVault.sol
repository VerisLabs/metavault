/// SPDX-License-Identifer: MIT
pragma solidity ^0.8.19;

import { IERC4626Oracle, ISuperformGateway } from "interfaces/Lib.sol";
import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { Multicallable } from "solady/utils/Multicallable.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { SignatureCheckerLib } from "solady/utils/SignatureCheckerLib.sol";

import {
    Harvest,
    LiqRequest,
    MultiDstMultiVaultStateReq,
    MultiDstSingleVaultStateReq,
    MultiVaultSFData,
    MultiXChainMultiVaultWithdraw,
    MultiXChainSingleVaultWithdraw,
    ProcessRedeemRequestWithSignatureParams,
    SingleDirectMultiVaultStateReq,
    SingleDirectSingleVaultStateReq,
    SingleVaultSFData,
    SingleXChainMultiVaultStateReq,
    SingleXChainMultiVaultWithdraw,
    SingleXChainSingleVaultStateReq,
    SingleXChainSingleVaultWithdraw,
    VaultConfig,
    VaultData,
    VaultLib,
    VaultReport
} from "./types/Lib.sol";

import { Base } from "src/common/Base.sol";

/// @title MetaVault
/// @author Unlockd
/// @notice A ERC750 vault implementation for cross-chain yield
/// aggregation
contract MetaVault is Base, MultiCallable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           LIBRARIES                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Safe casting operations for uint
    using SafeCastLib for uint256;

    /// @dev Safe transfer operations for ERC20 tokens
    using SafeTransferLib for address;

    /// @dev Library for vault-related operations
    using VaultLib for VaultData;

    /// @dev Library for math
    using Math for uint256;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Emitted when a redeem request is processed
    event ProcessRedeemRequest(address indexed controller, uint256 shares);

    /// @dev Emitted when a redeem request is fulfilled after being processed
    event FulfillRedeemRequest(address indexed controller, uint256 shares, uint256 assets);

    /// @dev Emitted when investing vault idle assets
    event Invest(uint256 amount);

    /// @dev Emitted when divesting vault idle assets
    event Divest(uint256 amount);

    /// @dev Emitted when cross-chain investment is settled
    event SettleXChainInvest(uint256 indexed superformId, uint256 assets);

    /// @dev Emitted when cross-chain investment is settled
    event SettleXChainDivest(uint256 indexed superformId, uint256 assets);

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

    /// @dev Emitted when updating the performance fee
    event SetPerformanceFee(uint16 fee);

    /// @dev Emitted when updating the oracle fee
    event SetOracleFee(uint16 fee);

    // @dev Emitted when updating the recovery address
    event SetRecoveryAddress(address recoveryAddress);

    /// @dev Emitted when the emergency shutdown state is changed
    event EmergencyShutdown(bool enabled);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Thrown when {msg.value} cannot cover the crosschain transaction cost
    error InsufficientGas();

    /// @notice Thrown when attempting to interact with a vault that is not listed in the portfolio
    error VaultNotListed();

    /// @notice Thrown when attempting to add a vault that is already listed
    error VaultAlreadyListed();

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

    /// @notice Modifier to update the share price water-mark before running a function
    modifier updateWatermark() {
        _;
        uint256 sp = sharePrice();
        assembly {
            let spwm := sload(sharePriceWaterMark.slot)
            if lt(spwm, sp) { sstore(sharePriceWaterMark.slot, sp) }
        }
    }

    constructor(VaultConfig memory config) {
        _asset = config.asset;
        _name = config.name;
        _symbol = config.symbol;
        treasury = config.treasury;
        managementFee = config.managementFee;
        performanceFee = config.performanceFee;
        oracleFee = config.oracleFee;
        recoveryAddress = config.recoveryAddress;
        sharesLockTime = config.sharesLockTime;
        processRedeemSettlement = config.processRedeemSettlement;
        lastReport = block.timestamp;
        hurdleRate = config.assetHurdleRate;

        // Try to get asset decimals, fallback to default if unsuccessful
        (bool success, uint8 result) = _tryGetAssetDecimals(config.asset);
        _decimals = success ? result : _DEFAULT_UNDERLYING_DECIMALS;
        // Set the chain ID for the current network
        THIS_CHAIN_ID = uint64(block.chainid);
        // Initialize chainIndexes mapping
        for (uint256 i = 0; i != N_CHAINS; i++) {
            chainIndexes[DST_CHAINS[i]] = i;
        }

        // Initialize ownership and grant admin role
        _initializeOwner(msg.sender);
        _grantRoles(msg.sender, ADMIN_ROLE);

        // Initialize signer relayer
        signerRelayer = config.signerRelayer;
    }

    /// @notice Sets the gateway contract for cross-chain communication
    /// @param _gateway The address of the new gateway contract
    /// @dev Only callable by addresses with ADMIN_ROLE
    function setGateway(ISuperformGateway _gateway) external onlyRoles(ADMIN_ROLE) {
        gateway = _gateway;
        asset().safeApprove(address(_gateway), type(uint256).max);
        gateway.superPositions().setApprovalForAll(address(_gateway), true);
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
        return gateway.totalpendingXChainInvests() + gateway.totalPendingXChainDivests() + totalWithdrawableAssets();
    }

    /// @notice Returns the total amount of the underlying asset that have been deposited into the vault.
    function totalDeposits() public view returns (uint256 assets) {
        return totalIdle() + totalDebt();
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

    /// @notice helper function to see if a vault is listed
    function isVaultListed(uint256 superformId) public view returns (bool) {
        return vaults[superformId].vaultAddress != address(0);
    }

    /// @notice returns the struct containtaining vault data
    function getVault(uint256 superformId) public view returns (VaultData memory vault) {
        return vaults[superformId];
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
        return super.withdraw(assets, receiver, controller);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VAULT MANAGEMENT                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Invests assets from this vault into a single target vault within the same chain
    /// @dev Only callable by addresses with the MANAGER_ROLE
    /// @param vaultAddress The address of the target vault to invest in
    /// @param assets The amount of assets to invest
    /// @param minSharesOut The minimum amount of shares expected to receive from the investment
    /// @return shares The number of shares received from the target vault
    function investSingleDirectSingleVault(
        address vaultAddress,
        uint256 assets,
        uint256 minSharesOut
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
        ERC4626(vaultAddress).deposit(assets, address(this));

        // Calculate the number of shares received
        shares = vaultAddress.balanceOf(address(this)) - balanceBefore;

        // Ensure the received shares meet the minimum expected assets
        if (shares < minSharesOut) {
            revert InsufficientAssets();
        }

        // Update the vault's internal accounting
        uint128 amountUint128 = assets.toUint128();
        _totalIdle -= amountUint128;
        _totalDebt += amountUint128;
        vaults[_vaultToSuperformId[vaultAddress]].totalDebt += amountUint128;

        emit Invest(assets);
        return shares;
    }

    /// @notice Invests assets from this vault into multiple target vaults within the same chain
    /// @dev Calls investSingleDirectSingleVault for each target vault
    /// @param vaultAddresses An array of addresses of the target vaults to invest in
    /// @param assets An array of amounts to invest in each corresponding vault
    /// @param minSharesOuts An array of minimum amounts of shares expected from each investment
    /// @return shares An array of the number of shares received from each target vault
    function investSingleDirectMultiVault(
        address[] calldata vaultAddresses,
        uint256[] calldata assets,
        uint256[] calldata minSharesOuts
    )
        external
        returns (uint256[] memory shares)
    {
        shares = new uint256[](vaultAddresses.length);
        for (uint256 i = 0; i < vaultAddresses.length; ++i) {
            shares[i] = investSingleDirectSingleVault(vaultAddresses[i], assets[i], minSharesOuts[i]);
        }
    }

    /// @notice Invests assets from this vault into a single target vault on a different chain
    /// @dev Only callable by addresses with the MANAGER_ROLE
    /// @param req Crosschain deposit request
    function investSingleXChainSingleVault(SingleXChainSingleVaultStateReq calldata req)
        external
        payable
        onlyRoles(MANAGER_ROLE)
    {
        gateway.investSingleXChainSingleVault{ value: msg.value }(req);

        // Update the vault's internal accounting
        uint256 amount = req.superformData.amount;
        uint128 amountUint128 = amount.toUint128();
        _totalIdle -= amountUint128;

        emit Invest(amount);
    }

    /// @notice Placeholder for investing in multiple vaults across chains
    /// @param req Crosschain deposit request
    function investSingleXChainMultiVault(SingleXChainMultiVaultStateReq calldata req)
        external
        payable
        onlyRoles(MANAGER_ROLE)
    {
        uint256 totalAmount = gateway.investSingleXChainMultiVault{ value: msg.value }(req);
        _totalIdle -= totalAmount.toUint128();
        emit Invest(totalAmount);
    }

    /// @notice Placeholder for investing multiple assets in a single vault across chains
    /// @dev Not implemented yet
    function investMultiXChainSingleVault(MultiDstSingleVaultStateReq calldata req)
        external
        payable
        onlyRoles(MANAGER_ROLE)
    {
        uint256 totalAmount = gateway.investMultiXChainSingleVault{ value: msg.value }(req);
        _totalIdle -= totalAmount.toUint128();
        emit Invest(totalAmount);
    }

    /// @notice Placeholder for investing multiple assets in multiple vaults across chains
    /// @dev Not implemented yet
    function investMultiXChainMultiVault(MultiDstMultiVaultStateReq calldata req)
        external
        payable
        onlyRoles(MANAGER_ROLE)
    {
        uint256 totalAmount = gateway.investMultiXChainMultiVault(req);
        _totalIdle -= totalAmount.toUint128();
        emit Invest(totalAmount);
    }

    /// @notice Withdraws assets from a single vault on the same chain
    /// @dev This function redeems shares from an ERC4626 vault and updates internal accounting.
    /// If all shares are withdrawn, it removes the total debt for that vault.
    /// Only callable by addresses with MANAGER_ROLE.
    /// @param vaultAddress The address of the vault to withdraw from
    /// @param shares The amount of shares to redeem
    /// @param minAssetsOut The minimum amount of assets expected to receive
    /// @return assets The amount of assets actually withdrawn
    function divestSingleDirectSingleVault(
        address vaultAddress,
        uint256 shares,
        uint256 minAssetsOut
    )
        public
        onlyRoles(MANAGER_ROLE)
        returns (uint256 assets)
    {
        uint256 sharesBalance = ERC4626(vaultAddress).balanceOf(address(this));
        uint256 sharesValue = ERC4626(vaultAddress).convertToAssets(shares).toUint128();
        bool removeDebt;
        if (shares == sharesBalance) {
            removeDebt = true;
        }

        // Ensure the target vault is in the approved list
        if (!isVaultListed(vaultAddress)) revert VaultNotListed();

        // Record the balance before deposit to calculate received assets
        uint256 balanceBefore = asset().balanceOf(address(this));

        // Deposit assets into the target vault
        ERC4626(vaultAddress).redeem(shares, address(this), address(this));

        // Calculate the number of assets received
        assets = asset().balanceOf(address(this)) - balanceBefore;

        // Ensure the received assets meet the minimum expected amount
        if (assets < minAssetsOut) {
            revert InsufficientAssets();
        }

        // Update the vault's internal accounting
        _totalIdle += assets.toUint128();
        uint128 amountUint128 =
            removeDebt ? vaults[_vaultToSuperformId[vaultAddress]].totalDebt : sharesValue.toUint128();
        _totalDebt -= amountUint128;
        vaults[_vaultToSuperformId[vaultAddress]].totalDebt -= amountUint128;

        emit Divest(sharesValue);
        return assets;
    }

    /// @notice Withdraws assets from multiple vaults on the same chain
    /// @dev Iteratively calls divestSingleDirectSingleVault for each vault.
    /// Only callable by addresses with MANAGER_ROLE.
    /// @param vaultAddresses Array of vault addresses to withdraw from
    /// @param shares Array of share amounts to withdraw from each vault
    /// @param minAssetsOuts Array of minimum expected asset amounts for each withdrawal
    /// @return assets Array of actual asset amounts withdrawn from each vault
    function divestSingleDirectMultiVault(
        address[] calldata vaultAddresses,
        uint256[] calldata shares,
        uint256[] calldata minAssetsOuts
    )
        external
        payable
        returns (uint256[] memory assets)
    {
        assets = new uint256[](vaultAddresses.length);
        for (uint256 i = 0; i < vaultAddresses.length; ++i) {
            assets[i] = divestSingleDirectSingleVault(vaultAddresses[i], shares[i], minAssetsOuts[i]);
        }
    }

    /// @notice Withdraws assets from a single vault on a different chain
    /// @dev Initiates a cross-chain withdrawal through the gateway contract.
    /// Updates debt tracking for the source vault.
    /// Only callable by addresses with MANAGER_ROLE.
    /// @param req The withdrawal request containing target chain, vault, and amount details
    function divestSingleXChainSingleVault(SingleXChainSingleVaultStateReq calldata req)
        external
        payable
        onlyRoles(MANAGER_ROLE)
    {
        uint256 sharesValue = gateway.divestSingleXChainSingleVault{ value: msg.value }(req);
        _totalDebt = _sub0(_totalDebt, sharesValue).toUint128();
        vaults[req.superformData.superformId].totalDebt =
            _sub0(vaults[req.superformData.superformId].totalDebt, sharesValue).toUint128();
        emit Divest(sharesValue);
    }

    /// @notice Withdraws assets from multiple vaults on a single different chain
    /// @dev Processes withdrawals from multiple vaults on the same target chain.
    /// Updates debt tracking for all source vaults.
    /// Only callable by addresses with MANAGER_ROLE.
    /// @param req The withdrawal request containing target chain and multiple vault details
    function divestSingleXChainMultiVault(SingleXChainMultiVaultStateReq calldata req)
        external
        payable
        onlyRoles(MANAGER_ROLE)
    {
        for (uint256 i = 0; i < req.superformsData.superformIds.length;) {
            uint256 superformId = req.superformsData.superformIds[i];
            VaultData memory vault = vaults[superformId];
            uint256 sharesBalance = _sharesBalance(vault);
            uint256 sharesValue = vault.convertToAssets(sharesBalance, true);
            vault.totalDebt = _sub0(vaults[superformId].totalDebt, sharesValue).toUint128();
            vaults[superformId] = vault;
            unchecked {
                ++i;
            }
        }
        uint256 totalAmount = gateway.divestSingleXChainMultiVault{ value: msg.value }(req);
        _totalDebt = _sub0(_totalDebt, totalAmount).toUint128();
        emit Divest(totalAmount);
    }

    /// @notice Withdraws assets from a single vault across multiple chains
    /// @dev Initiates withdrawals from the same vault type across different chains.
    /// Updates debt tracking for all source vaults.
    /// Only callable by addresses with MANAGER_ROLE.
    /// @param req The withdrawal request containing multiple chain and single vault details
    function divestMultiXChainSingleVault(MultiDstSingleVaultStateReq calldata req)
        external
        payable
        onlyRoles(MANAGER_ROLE)
    {
        for (uint256 i = 0; i < req.superformsData.length;) {
            uint256 superformId = req.superformsData[i].superformId;
            VaultData memory vault = vaults[superformId];
            uint256 sharesBalance = _sharesBalance(vault);
            uint256 sharesValue = vault.convertToAssets(sharesBalance, true);
            vault.totalDebt = _sub0(vaults[superformId].totalDebt, sharesValue).toUint128();
            vaults[superformId] = vault;
            unchecked {
                ++i;
            }
        }
        uint256 totalAmount = gateway.divestMultiXChainSingleVault{ value: msg.value }(req);
        _totalDebt = _sub0(_totalDebt, totalAmount).toUint128();
        emit Divest(totalAmount);
    }

    /// @notice Withdraws assets from multiple vaults across multiple chains
    /// @dev Processes withdrawals from different vaults across multiple chains.
    /// Updates debt tracking for all source vaults.
    /// Only callable by addresses with MANAGER_ROLE.
    /// @param req The withdrawal request containing multiple chain and multiple vault details
    function divestMultiXChainMultiVault(MultiDstMultiVaultStateReq calldata req)
        external
        payable
        onlyRoles(MANAGER_ROLE)
    {
        for (uint256 i = 0; i < req.superformsData.length;) {
            uint256[] memory superformIds = req.superformsData[i].superformIds;
            for (uint256 j = 0; j < superformIds.length;) {
                uint256 superformId = superformIds[j];
                VaultData memory vault = vaults[superformId];
                uint256 sharesBalance = _sharesBalance(vault);
                uint256 sharesValue = vault.convertToAssets(sharesBalance, true);
                vault.totalDebt = _sub0(vaults[superformId].totalDebt, sharesValue).toUint128();
                vaults[superformId] = vault;
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
        uint256 totalAmount = gateway.divestMultiXChainMultiVault{ value: msg.value }(req);
        _totalDebt = _sub0(_totalDebt, totalAmount).toUint128();

        emit Divest(totalAmount);
    }

    /// @notice Updates the share prices of vaults based on oracle reports
    /// @dev This function can only be called by addresses with the ORACLE_ROLE
    function harvest(Harvest[] calldata harvests) external updateWatermark {
        uint256 duration = block.timestamp - lastReport;
        uint256 sharePrice_ = sharePrice();
        for (uint256 i = 0; i < harvests.length; i++) {
            // Cache the current report for efficiency
            Harvest memory _vault = harvests[i];

            // Ensure the reported vault is in the approved list
            if (!isVaultListed(_vault.vaultAddress)) revert VaultNotListed();

            // Retrieve the superform ID for the vault
            uint256 superformId = _vaultToSuperformId[_vault.vaultAddress];

            // Cache the vault data for easier access
            VaultData memory vault = vaults[superformId];

            // Get the current balance of vault shares
            uint256 sharesBalance = _sharesBalance(vault);

            // Calculate the total assets value before applying the new share price
            uint256 totalAssetsBefore = vault.convertToAssetsCachedSharePrice(sharesBalance);

            // Update the vault's share price with the new reported value
            VaultReport memory report = vault.oracle.getLatestSharePrice(_vault.chainId, _vault.vaultAddress);

            vaults[superformId].lastReportedSharePrice = uint192(report.sharePrice);

            // Calculate the total assets value after applying the new share price
            uint256 totalAssetsAfter = vault.convertToAssets(sharesBalance, true);

            // Gains/losses of the strategy
            int256 vaultDelta = int256(totalAssetsAfter) - int256(totalAssetsBefore);

            // If it has profit apply fees
            if (vaultDelta > 0) {
                // Only charge fees on yield above watermark
                if (sharePrice_ > sharePriceWaterMark) {
                    // And only charge rees if the strategy yield is above hurdle rate
                    uint256 rate = (uint256(vaultDelta) * MAX_BPS).mulDiv(SECS_PER_YEAR, duration) / totalAssetsBefore;
                    if (rate > hurdleRate) {
                        uint16 effectiveFee = performanceFee - vault.deductedFees;
                        uint256 performanceFees = uint256(vaultDelta) * effectiveFee / MAX_BPS;
                        uint256 performanceFeeShares = convertToShares(performanceFees);
                        _mint(treasury, performanceFeeShares);
                    }
                }
            }

            // Calculate and distribute management fees based on the change in total assets
            _assessOracleFees(report.reporter, duration);
            emit Report(vault.chainId, vault.vaultAddress, vaultDelta);
        }
        // Calculate and distribute management fees based on the change in total assets
        _assessManagementFees(treasury, duration);
        // Update timestamp of last report
        lastReport = block.timestamp;
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
        uint16 deductedFees,
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
        vaults[superformId].deductedFees = deductedFees;
        uint192 lastSharePrice = vaults[superformId].sharePrice().toUint192();
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

    /// @notice sets the annually management fee
    /// @param _performanceFee new BPS management fee
    function setPerformanceFee(uint16 _performanceFee) external onlyRoles(ADMIN_ROLE) {
        performanceFee = _performanceFee;
        emit SetPerformanceFee(_performanceFee);
    }

    /// @notice sets the annually oracle fee
    /// @param _oracleFee new BPS oracle fee
    function setOracleFee(uint16 _oracleFee) external onlyRoles(ADMIN_ROLE) {
        oracleFee = _oracleFee;
        emit SetOracleFee(_oracleFee);
    }

    /// @notice Sets the recovery address for the vault
    /// @dev The recovery address is used as a safety mechanism for recovering assets in emergency situations.
    /// Only callable by addresses with ADMIN_ROLE.
    /// @param _recoveryAddress The new address to be set as the recovery address
    function setRecoveryAddress(address _recoveryAddress) external onlyRoles(ADMIN_ROLE) {
        recoveryAddress = _recoveryAddress;
        emit SetRecoveryAddress(_recoveryAddress);
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

    /// @notice Accepts a donation of assets to the vault
    /// @param assets The amount of assets to donate
    /// @dev Increases the total idle assets of the vault
    function donate(uint256 assets) external {
        asset().safeTransferFrom(msg.sender, address(this), assets);
        _totalIdle += assets.toUint128();
    }

    /// @notice Settles a cross-chain investment by updating vault accounting
    /// @param superformId The ID of the superform being settled
    /// @param bridgedAssets The amount of assets that were bridged
    /// @dev Only callable by the gateway contract
    function settleXChainInvest(uint256 superformId, uint256 bridgedAssets) public {
        if (msg.sender != address(gateway)) revert Unauthorized();
        _totalDebt += bridgedAssets.toUint128();
        vaults[superformId].totalDebt += bridgedAssets.toUint128();
        emit SettleXChainInvest(superformId, bridgedAssets);
    }

    /// @notice Settles a cross-chain divestment by updating vault accounting
    /// @param superformId The ID of the superform being settled
    /// @param withdrawnAssets The amount of assets that were withdrawn
    /// @dev Only callable by the gateway contract
    function settleXChainDivest(uint256 superformId, uint256 withdrawnAssets) public {
        if (msg.sender != address(gateway)) revert Unauthorized();
        _totalIdle += withdrawnAssets.toUint128();
        emit SettleXChainDivest(superformId, withdrawnAssets);
    }

    /// @notice the number of decimals of the underlying token
    function _underlyingDecimals() internal view override returns (uint8) {
        return _decimals;
    }

    /// @notice Applies annualized fees to vault assets
    /// @notice Mints shares to the treasury
    function _assessManagementFees(address managementFeeReceiver, uint256 duration) private {
        uint256 managementFees = (totalAssets() * duration * managementFee) / SECS_PER_YEAR / MAX_BPS;
        uint256 managementFeeShares = convertToShares(managementFees);

        _mint(managementFeeReceiver, managementFeeShares);
    }

    /// @notice Applies annualized fees to vault assets
    /// @notice Mints shares to the treasury
    function _assessOracleFees(address oracleFeeReceiver, uint256 duration) private {
        uint256 oracleFees = (totalAssets() * duration * oracleFee) / SECS_PER_YEAR / MAX_BPS;
        uint256 oracleFeeShares = convertToShares(oracleFees);

        _mint(oracleFeeReceiver, oracleFeeShares);
    }

    /// @dev Hook that is called after any deposit or mint.
    function _afterDeposit(uint256 assets, uint256 /*uint shares*/ ) internal override {
        uint128 assetsUint128 = assets.toUint128();
        _totalIdle += assetsUint128;
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
        if (from != address(gateway)) revert Unauthorized();
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
        values;
        data;
        if (from != address(gateway)) revert Unauthorized();
        return this.onERC1155BatchReceived.selector;
    }
}
