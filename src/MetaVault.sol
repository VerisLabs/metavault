/// SPDX-License-Identifer: MIT
pragma solidity ^0.8.19;

import { ISharePriceOracle, ISuperformGateway } from "interfaces/Lib.sol";
import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { Multicallable } from "solady/utils/Multicallable.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import {
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
} from "types/Lib.sol";

import { MultiFacetProxy } from "common/Lib.sol";

/// @title MetaVault
/// @author Unlockd
/// @notice A ERC750 vault implementation for cross-chain yield
/// aggregation
contract MetaVault is MultiFacetProxy, Multicallable {
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

    /// @dev Emitted when a redeem request is fulfilled after being processed
    event FulfillRedeemRequest(address indexed controller, uint256 shares, uint256 assets);

    /// @dev Emitted when fees are applied to a user
    event AssessFees(address indexed controller, uint256 managementFees, uint256 performanceFees, uint256 oracleFees);

    /// @dev Emitted when investing vault idle assets
    event Invest(uint256 amount);

    /// @dev Emitted when divesting vault idle assets
    event Divest(uint256 amount);

    /// @dev Emitted when cross-chain investment is settled
    event SettleXChainInvest(uint256 indexed superformId, uint256 assets);

    /// @dev Emitted when cross-chain investment is settled
    event SettleXChainDivest(uint256 assets);

    /// @dev Emitted when investing vault idle assets
    event Report(uint64 indexed chainId, address indexed vault, int256 amount);

    /// @dev Emitted when adding a new vault to the portfolio
    event AddVault(uint64 indexed chainId, address vault);

    /// @dev Emitted when updating the shares lock time
    event SetSharesLockTime(uint24 time);

    /// @dev Emitted when updating the management fee
    event SetManagementFee(uint16 fee);

    /// @dev Emitted when updating the performance fee
    event SetPerformanceFee(uint16 fee);

    /// @dev Emitted when updating the oracle fee
    event SetOracleFee(uint16 fee);

    /// @dev Emitted when the emergency shutdown state is changed
    event EmergencyShutdown(bool enabled);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Thrown when there are not enough assets to fulfill a request
    error InsufficientAssets();

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
    modifier updateGlobalWatermark() {
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
        isOperator[treasury][address(this)] = true;
        emit OperatorSet(treasury, address(this), true);
        managementFee = config.managementFee;
        performanceFee = config.performanceFee;
        oracleFee = config.oracleFee;
        sharesLockTime = config.sharesLockTime;
        lastReport = block.timestamp;
        _baseHurdleRate = config.assetHurdleRate;

        // Try to get asset decimals, fallback to default if unsuccessful
        (bool success, uint8 result) = _tryGetAssetDecimals(config.asset);
        _decimals = success ? result : _DEFAULT_UNDERLYING_DECIMALS;
        // Set the chain ID for the current network
        THIS_CHAIN_ID = uint64(block.chainid);
        // Initialize chainIndexes mapping
        for (uint256 i = 0; i != N_CHAINS; i++) {
            chainIndexes[DST_CHAINS[i]] = i;
        }

        lastFeesCharged = block.timestamp;

        // Initialize ownership and grant admin role
        _initializeOwner(msg.sender);
        _grantRoles(msg.sender, ADMIN_ROLE);

        // Initialize signer relayer
        signerRelayer = config.signerRelayer;

        // Set initial watermark
        sharePriceWaterMark = 10 ** decimals();
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
        return shares;
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

    /// @dev Override to update the average entry price and the timestamp of last redeem
    function _deposit(
        uint256 assets,
        uint256 shares,
        address receiver,
        address controller
    )
        internal
        override
        returns (uint256 assetsReturn, uint256 sharesReturn)
    {
        _updatePosition(controller, shares);
        if (lastRedeem[controller] == 0) lastRedeem[controller] = block.timestamp;
        return super._deposit(assets, shares, receiver, controller);
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
        assets = super.redeem(shares, receiver, controller);
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

    struct TempWithdrawData {
        uint256 entrySharePrice;
        uint256 currentSharePrice;
        int256 assetsDelta;
        uint256 duration;
        uint256 performanceFeeExempt;
        uint256 managementFeeExempt;
        uint256 oracleFeeExempt;
        uint256 performanceFees;
        uint256 managementFees;
        uint256 oracleFees;
        uint256 totalFees;
    }

    /// @dev Override to apply fees on exit
    function _withdraw(
        uint256 assets,
        uint256 shares,
        address receiver,
        address controller
    )
        internal
        override
        returns (uint256 assetsReturn, uint256 sharesReturn)
    {
        TempWithdrawData memory temp;
        // Get the price metrics needed for calculations
        temp.entrySharePrice = positions[controller];
        temp.currentSharePrice = sharePrice();

        // Consume claimable
        unchecked {
            _claimableRedeemRequest[controller].assets -= assets;
            _claimableRedeemRequest[controller].shares -= shares;
        }

        temp.duration = block.timestamp - Math.max(lastRedeem[controller], lastFeesCharged);
        lastRedeem[controller] = block.timestamp;

        // Get fee exemptions for this controller
        temp.performanceFeeExempt = performanceFeeExempt[controller];
        temp.managementFeeExempt = managementFeeExempt[controller];
        temp.oracleFeeExempt = oracleFeeExempt[controller];

        // Calculate time-based fees (management & oracle)
        // These are charged on total assets, prorated for the time period
        temp.managementFees =
            (assets * temp.duration).fullMulDiv(_sub0(managementFee, temp.managementFeeExempt), SECS_PER_YEAR) / MAX_BPS;
        temp.oracleFees =
            (assets * temp.duration).fullMulDiv(_sub0(oracleFee, temp.oracleFeeExempt), SECS_PER_YEAR) / MAX_BPS;
        assets -= temp.managementFees + temp.oracleFees;
        temp.totalFees += temp.managementFees + temp.oracleFees;

        // Calculate the asset's value change since entry
        // This gives us the raw profit/loss in asset terms
        temp.assetsDelta = int256(assets) - (int256(shares) * int256(temp.entrySharePrice) / int256(10 ** decimals()));

        // Only calculate fees if there's a profit
        if (temp.assetsDelta > 0) {
            uint256 totalReturn = uint256(temp.assetsDelta);
            // Calculate returns relative to hurdle rate
            uint256 hurdleReturn = (assets * hurdleRate()).fullMulDiv(temp.duration, SECS_PER_YEAR) / MAX_BPS;
            uint256 excessReturn;

            // Only charge performance fees if:
            // 1. Current share price is not below
            // 2. Returns exceed hurdle rate
            if (temp.currentSharePrice > sharePriceWaterMark && totalReturn > hurdleReturn) {
                // Only charge performance fees on returns above hurdle rate
                excessReturn = totalReturn - hurdleReturn;

                temp.performanceFees = excessReturn * _sub0(performanceFee, temp.performanceFeeExempt) / MAX_BPS;
            }
            // Calculate total fees
            temp.totalFees += temp.performanceFees;
        }

        // Transfer fees to treasury if any were charged
        if (temp.totalFees > 0) {
            // mint shares for treasury
            _mint(treasury, convertToShares(temp.totalFees));
            _afterDeposit(temp.totalFees, 0);
        }

        // Transfer remaining assets to receiver
        uint256 totalAssetsAfterFee = assets - temp.totalFees;
        asset().safeTransfer(receiver, totalAssetsAfterFee);

        {
            uint256 managementFees = temp.managementFees;
            uint256 performanceFees = temp.performanceFees;
            uint256 oracleFees = temp.oracleFees;
            // Emit events
            /// @solidity memory-safe-assembly
            assembly {
                // Emit the {Withdraw} event
                mstore(0x00, totalAssetsAfterFee)
                mstore(0x20, shares)
                let m := shr(96, not(0))
                log4(
                    0x00,
                    0x40,
                    0xfbde797d201c681b91056529119e0b02407c7bb96a4a2c75c01fc9667232c8db,
                    and(m, controller),
                    and(m, receiver),
                    and(m, controller)
                )
                // Emit the {AssessFees} event
                mstore(0x00, managementFees)
                mstore(0x20, performanceFees)
                mstore(0x40, oracleFees)
                log2(0x00, 0x60, 0xa443e1db11cb46c65620e8e21d4830a6b9b444fa4c350f0dd0024b8a5a6b6ef5, and(m, controller))
            }
        }

        return (totalAssetsAfterFee, shares);
    }

    /// @notice Returns the base hurdle rate for performance fee calculations
    /// @dev The hurdle rate differs by asset:
    /// - For stablecoins (USDC): Typically set to T-Bills yield (e.g., 5.5% APY)
    /// - For ETH: Typically set to base staking return like Lido (e.g., 3.5% APY)
    /// @return uint256 The current base hurdle rate in basis points
    function hurdleRate() public view returns (uint256) {
        return _baseHurdleRate;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VAULT MANAGEMENT                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @notice Charges global management, performance, and oracle fees on the vault's total assets
    /// @dev Fee charging mechanism works as follows:
    /// 1. Time-based fees (management & oracle) are charged on total assets, prorated for the time period
    /// 2. Performance fees are only charged if two conditions are met:
    ///    a) Current share price is above the watermark (high water mark)
    ///    b) Returns exceed the hurdle rate
    /// 3. The hurdle rate is asset-specific:
    ///    - For stablecoins (e.g., USDC): typically tied to T-Bill yields
    ///    - For ETH: typically tied to base staking returns (e.g., Lido APY)
    /// 4. Performance fees are only charged on excess returns above both:
    ///    - The watermark (preventing double-charging on same gains)
    ///    - The hurdle rate (ensuring fees only on excess performance)
    /// Example calculation:
    /// - If initial assets = $1M, current assets = $1.08M
    /// - Duration = 180 days, Management = 2%, Oracle = 0.5%, Performance = 20%
    /// - Hurdle = 5% APY
    /// Then:
    /// 1. Management Fee = $1.08M * 2% * (180/365) = $10,628
    /// 2. Oracle Fee = $1.08M * 0.5% * (180/365) = $2,657
    /// 3. Hurdle Return = $1M * 5% * (180/365) = $24,657
    /// 4. Excess Return = ($80,000 - $13,285 - $24,657) = $42,058
    /// 5. Performance Fee = $42,058 * 20% = $8,412
    /// @return uint256 Total fees charged
    function chargeGlobalFees() external updateGlobalWatermark onlyRoles(MANAGER_ROLE) returns (uint256) {
        uint256 currentSharePrice = sharePrice();
        uint256 lastSharePrice = sharePriceWaterMark;
        uint256 duration = block.timestamp - lastFeesCharged;
        uint256 currentTotalAssets = totalAssets();
        uint256 lastTotalAssets = totalSupply().fullMulDiv(lastSharePrice, 10 ** decimals());

        // Calculate time-based fees (management & oracle)
        // These are charged on total assets, prorated for the time period
        uint256 managementFees = (currentTotalAssets * duration).fullMulDiv(managementFee, SECS_PER_YEAR) / MAX_BPS;
        uint256 oracleFees = (currentTotalAssets * duration).fullMulDiv(oracleFee, SECS_PER_YEAR) / MAX_BPS;
        uint256 totalFees = managementFees + oracleFees;
        uint256 performanceFees;

        currentTotalAssets += managementFees + oracleFees;

        lastFeesCharged = block.timestamp;

        // Calculate the asset's value change since entry
        // This gives us the raw profit/loss in asset terms
        int256 assetsDelta = int256(currentTotalAssets) - int256(lastTotalAssets);

        // Only calculate fees if there's a profit
        if (assetsDelta > 0) {
            uint256 excessReturn;

            // Calculate returns relative to hurdle rate
            uint256 hurdleReturn = (lastTotalAssets * hurdleRate()).fullMulDiv(duration, SECS_PER_YEAR) / MAX_BPS;
            uint256 totalReturn = uint256(assetsDelta);

            // Only charge performance fees if:
            // 1. Current share price is not below
            // 2. Returns exceed hurdle rate
            if (currentSharePrice > sharePriceWaterMark && totalReturn > hurdleReturn) {
                // Only charge performance fees on returns above hurdle rate
                excessReturn = totalReturn - hurdleReturn;

                performanceFees = excessReturn * performanceFee / MAX_BPS;
            }

            // Calculate total fees
            totalFees += performanceFees;
        }
        // Transfer fees to treasury if any were charged
        if (totalFees > 0) {
            _mint(treasury, convertToShares(totalFees));
            _afterDeposit(totalFees, 0);
        }
        assembly {
            let m := shr(96, not(0))

            // Emit the {AssessFees} event
            mstore(0x00, managementFees)
            mstore(0x20, performanceFees)
            mstore(0x40, oracleFees)
            log2(0x00, 0x60, 0xa443e1db11cb46c65620e8e21d4830a6b9b444fa4c350f0dd0024b8a5a6b6ef5, and(m, address()))
        }
        return totalFees;
    }

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
        ISharePriceOracle oracle
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

    /// @notice Whitelists specific clients so they pay less or zero fees
    function setFeeExcemption(
        address controller,
        uint256 managementFeeExcemption,
        uint256 performanceFeeExcemption,
        uint256 oracleFeeExcemption
    )
        external
        onlyRoles(ADMIN_ROLE)
    {
        performanceFeeExempt[controller] = performanceFeeExcemption;
        managementFeeExempt[controller] = managementFeeExcemption;
        oracleFeeExempt[controller] = oracleFeeExcemption;
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

    /// @notice Allows direct donation of assets to the vault
    /// @dev Transfers assets from sender to vault and updates idle balance
    /// @param assets The amount of assets to donate
    function donate(uint256 assets) external {
        asset().safeTransferFrom(msg.sender, address(this), assets);
        _afterDeposit(assets, 0);
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
    /// @param withdrawnAssets The amount of assets that were withdrawn
    /// @dev Only callable by the gateway contract
    function settleXChainDivest(uint256 withdrawnAssets) public {
        if (msg.sender != address(gateway)) revert Unauthorized();
        _totalIdle += withdrawnAssets.toUint128();
        emit SettleXChainDivest(withdrawnAssets);
    }

    /// @notice the number of decimals of the underlying token
    function _underlyingDecimals() internal view override returns (uint8) {
        return _decimals;
    }

    /// @notice Updates the average entry share price of a controller
    function _updatePosition(address controller, uint256 mintedShares) internal {
        uint256 averateEntryPrice = positions[controller];
        uint256 currentSharePrice = sharePrice();
        uint256 sharesBalance = balanceOf(controller);
        if (averateEntryPrice == 0 || sharesBalance == 0) {
            positions[controller] = currentSharePrice;
        } else {
            uint256 totalCost = sharesBalance * averateEntryPrice + mintedShares * currentSharePrice;
            uint256 newTotalAmount = sharesBalance + mintedShares;
            uint256 newAverageEntryPrice = totalCost / newTotalAmount;
            positions[controller] = newAverageEntryPrice;
        }
    }

    /// @dev Hook that is called after any deposit or mint.
    function _afterDeposit(uint256 assets, uint256 /*uint shares*/ ) internal override {
        uint128 assetsUint128 = assets.toUint128();
        _totalIdle += assetsUint128;
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

    /// @dev
    function convertToSuperPositions(uint256 superformId, uint256 assets) external view returns (uint256) {
        return vaults[superformId].convertToShares(assets, false);
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
        if (from != address(gateway)) revert Unauthorized();
        if (data.length > 0) {
            uint256 refundedAssets = abi.decode(data, (uint256));
            if (refundedAssets != 0) {
                _totalDebt += refundedAssets.toUint128();
                vaults[superformId].totalDebt += refundedAssets.toUint128();
            }
        }
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
