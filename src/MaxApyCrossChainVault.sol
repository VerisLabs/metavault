/// SPDX-License-Identifer: MIT
pragma solidity 0.8.21;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { ERC7540, ReentrancyGuard } from "./lib/Lib.sol";
import { ISuperPositions, IBaseRouter, ISuperformFactory } from "./interfaces/Lib.sol";
import "./types/Lib.sol";

/// @title MaxApyCrossChainVault
/// @author Unlockd
/// notice description
contract MaxApyCrossChainVault is ERC7540, OwnableRoles, ReentrancyGuard {
    using SafeCastLib for uint256;
    using SafeTransferLib for address;
    using VaultLib for VaultData;
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev `keccak256(bytes("Withdraw(address,address,address,uint256,uint256)"))`.
    uint256 private constant _WITHDRAW_EVENT_SIGNATURE =
        0xfbde797d201c681b91056529119e0b02407c7bb96a4a2c75c01fc9667232c8db;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           CONSTANTS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    uint256 public constant WITHDRAWAL_QUEUE_SIZE = 30;
    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant EMERGENCY_ADMIN_ROLE = _ROLE_1;
    uint256 public constant ORACLE_ROLE = _ROLE_2;
    uint256 public constant INVESTOR_ROLE = _ROLE_3;
    uint256 public constant RELAYER_ROLE = _ROLE_4;

    uint64 public constant THIS_CHAIN_ID = 137;
    uint256 public constant N_CHAINS = 7;
    uint64[N_CHAINS] public DST_CHAINS = [
        1, // Ethereum Mainnet
        THIS_CHAIN_ID, // Polygon
        56, // Bnb
        10, // Optimism
        8453, // Base
        42_161, // Arbitrum One
        43_114 // Avalanche
    ];
    mapping(uint64 => uint256) chainIndexes;
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STORAGE                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // -- Slot 0
    /// @notice Cached value of total assets managed by the vault
    uint128 private _totalAssets;
    /// @notice Cached value of total assets in this vault
    uint128 private _totalIdle;
    // -- Slot 1
    /// @notice Cached value of total allocated assets
    uint128 private _totalDebt;
    /// @notice Asset decimals
    uint8 _decimals;
    /// @notice Protocol fee
    uint16 public managementFee;
    /// @notice Minimum time users must wait to redeem shares
    uint24 public sharesLockTime;
    /// @notice Wether the vault is paused
    bool public emergencyShutdown;
    /// @notice AutoPilot
    bool public autoPilot;
    // -- Slot  2
    /// @notice Fee receiver
    address public treasury;
    /// @notice Underlying asset
    address private immutable _asset;
    /// @notice Superform ERC1155 Superpositions
    ISuperPositions private _superPositions;
    /// @notice Superform Router
    IBaseRouter private _vaultRouter;
    /// @notice Superform Factory to validate superforms
    ISuperformFactory private _factory;
    /// @notice ERC20 name
    string private _name;
    /// @notice ERC20 symbol
    string private _symbol;
    /// @notice maps the assets and data of each allocated vault
    mapping(uint256 => VaultData) public vaults;
    /// @notice the ERC4626 oracle of each chain
    mapping(uint64 chain => address) public oracles;
    /// @notice Maximum number of vaults the vault can invest in
    uint256[WITHDRAWAL_QUEUE_SIZE] public withdrawalQueue;
    /// @notice Timestamp of deposit lock
    mapping(address => uint256) lockCheckpoint;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           MODIFIERS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier noEmergencyShutdown() {
        if (emergencyShutdown) {
            revert();
        }
        _;
    }

    constructor(
        address _asset_,
        string memory _name_,
        string memory _symbol_,
        uint16 _managementFee,
        uint24 _sharesLockTime
    ) {
        _asset = _asset_;
        _name = _name_;
        _symbol = _symbol_;
        managementFee = _managementFee;
        sharesLockTime = _sharesLockTime;
        (bool success, uint8 result) = _tryGetAssetDecimals(_asset_);
        _decimals = success ? result : _DEFAULT_UNDERLYING_DECIMALS;
        for (uint256 i = 0; i != N_CHAINS; i++) {
            chainIndexes[DST_CHAINS[i]] = i;
        }
        _grantRoles(msg.sender, ADMIN_ROLE);
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function asset() public view override returns (address) {
        return _asset;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @dev returns the total assets held by the vault
    function totalAssets() public view override returns (uint256 assets) {
        return _totalAssets;
    }

    function sharePrice() public view returns (uint256) {
        return convertToAssets(10 ** decimals());
    }

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
        _fulfillDepositRequest(controller, assets, convertToShares(assets));
    }

    function depositAtomic(uint256 assets, address to) public returns (uint256 shares) {
        requestDeposit(assets, msg.sender, msg.sender);
        shares = deposit(assets, to, msg.sender);
    }

    function mintAtomic(uint256 shares, address to) public returns (uint256 assets) {
        assets = convertToAssets(shares);
        requestDeposit(assets, msg.sender, msg.sender);
        assets = mint(shares, to, msg.sender);
    }

    function deposit(uint256 assets, address to) public override returns (uint256 shares) {
        return deposit(assets, to, msg.sender);
    }

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
        _lockShares(to, sharesBalance, shares);
        _afterDeposit(assets, shares);
    }

    function mint(uint256 shares, address to) public override returns (uint256 assets) {
        return mint(shares, to, msg.sender);
    }

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

    function _lockShares(address to, uint256 sharesBalance, uint256 newShares) internal {
        uint256 newBalance = sharesBalance + newShares;
        if (sharesBalance == 0) {
            lockCheckpoint[to] = block.timestamp;
        } else {
            lockCheckpoint[to] =
                (lockCheckpoint[to] * sharesBalance / newBalance) + (block.timestamp * newShares / newBalance);
        }
    }

    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    )
        public
        override
        returns (uint256 requestId)
    {
        _checkSharesLocked(controller);
        requestId = super.requestRedeem(shares, controller, owner);
        if (autoPilot) {
            _processRedeemRequest(shares, controller, owner, owner, true);
        }
    }

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
        return super.redeem(shares, receiver, controller);
    }

    function _checkSharesLocked(address owner) private view {
        if (block.timestamp < lockCheckpoint[owner] + sharesLockTime) revert();
    }

    function redeemAtomic(uint256 shares, address controller, address owner, address receiver) public nonReentrant {
        _checkSharesLocked(controller);
        _processRedeemRequest(shares, controller, owner, receiver, false);
    }

    // TODO: loop through the vaults to move the money
    function invest() external onlyRoles(INVESTOR_ROLE) {
        for (uint256 i = 0; i < WITHDRAWAL_QUEUE_SIZE; i++) { }
    }

    function processRedeemRequest(uint256 shares, address controller) external onlyRoles(RELAYER_ROLE) {
        _processRedeemRequest(shares, controller, controller, address(this), true);
    }

    function _prepareWithdralRoute(ProcessRequestCache memory cache) internal view {
        // Cache how many chains we need and how many vaults in each chain
        for (uint256 i = 0; i != WITHDRAWAL_QUEUE_SIZE; i++) {
            // If its fulfilled stop
            if (cache.amountToWithdraw == 0 || withdrawalQueue[i] == 0) {
                // reset
                cache.amountToWithdraw = cache.assets - _totalIdle;
                break;
            }
            // Cache next vault from the withdrawal queue
            VaultData memory vault = vaults[withdrawalQueue[i]];
            // Calcualate the maxWithdraw of the vault
            uint256 maxWithdraw = vault.convertToAssets(_superPositions.balanceOf(address(this), vault.superformId));
            // Dont withdraw more than max
            uint256 withdrawAssets = Math.min(maxWithdraw, cache.amountToWithdraw);
            // Cache chain index
            uint256 chainIndex = chainIndexes[vault.chainId];
            // Cache chain lenght
            uint256 len = cache.lens[chainIndex];
            // Push the superformId to the last index of the array
            cache.dstVaults[chainIndex][len] = vault.superformId;
            // Push the shares to redeeem of that vault
            cache.sharesPerVault[chainIndex][len] = vault.convertToShares(withdrawAssets);
            // If is in this chain shares will be instantly used
            if (vault.chainId == THIS_CHAIN_ID) {
                cache.sharesFulfilled += convertToShares(withdrawAssets);
            }
            // Reduce needed assets
            cache.amountToWithdraw -= withdrawAssets;
            // Increase index for iteration
            unchecked {
                cache.lens[chainIndex]++;
            }
        }
    }

    struct ProcessRequestCache {
        // List of vauts to withdraw from on each chain
        uint256[WITHDRAWAL_QUEUE_SIZE][N_CHAINS] dstVaults;
        // List of shares to redeem on each vault in each chain
        uint256[WITHDRAWAL_QUEUE_SIZE][N_CHAINS] sharesPerVault;
        // Cache length of list of each chain
        uint256[N_CHAINS] lens;
        // Assets to divest from other vaults
        uint256 amountToWithdraw;
        // Shares actually used
        uint256 sharesFulfilled;
        // Save assets that were withdrawn instantly
        uint256 totalClaimableWithdraw;
        // cache totalIdle
        uint256 totalIdle;
        // convert shares to assets at current price
        uint256 assets;
    }

    function _processRedeemRequest(
        uint256 shares,
        address controller,
        address owner,
        address receiver,
        bool retainAssets
    )
        internal
    {
        // Use struct to avoid stack too deep
        ProcessRequestCache memory cache;
        cache.totalIdle = _totalIdle;
        cache.assets = convertToShares(shares);
        // If totalIdle can covers the amount fulfill directly
        if (cache.totalIdle >= cache.assets) {
            cache.sharesFulfilled = shares;
            cache.totalClaimableWithdraw = cache.assets;
        }
        // Otherwise perform Superform withdrawals
        else {
            // Cache amount to withdraw before reducing totalIdle
            cache.amountToWithdraw = cache.assets - cache.totalIdle;
            // Use totalIdle to fulfill the request
            if (cache.totalIdle > 0) {
                cache.totalClaimableWithdraw = cache.totalIdle;
                cache.sharesFulfilled = convertToShares(cache.totalIdle);
            }
            /////////////////////////////////PREVIOUS CALCULATIONS ///////////////////////////////////////
            _prepareWithdralRoute(cache);
            ////////////////////////////////////// REDEEM FROM THIS CHAIN /////////////////////////////////////
            if (cache.lens[THIS_CHAIN_ID] > 0) {
                // Cache chain index
                uint256 chainIndex = chainIndexes[THIS_CHAIN_ID];
                if (cache.lens[THIS_CHAIN_ID] == 1) {
                    // shares to redeem
                    uint256 sharesAmount = cache.sharesPerVault[chainIndex][0];
                    // superformId(take first element fo the array)
                    uint256 superformId = cache.dstVaults[chainIndex][0];
                    // get actual withdrawn amount
                    uint256 withdrawn = _singleDirectSingleVaultWithdraw(superformId, sharesAmount, receiver);
                    // cache instant total withdraw
                    cache.totalClaimableWithdraw += withdrawn;
                    // cache shares to burn
                    cache.sharesFulfilled += convertToShares(withdrawn);
                    // Increase idle funds
                    _totalIdle += withdrawn.toUint128();
                    // Reduce vault debt
                    vaults[superformId].totalDebt -= vaults[superformId].convertToAssets(sharesAmount).toUint128();
                } else {
                    uint256 len = cache.lens[chainIndex];

                    // Prepare arguments for request using dynamic arrays
                    uint256[] memory superformIds = new uint256[](len);
                    uint256[] memory amounts = new uint256[](len);
                    // Cast fixed arrays to dynamic ones
                    for (uint256 i = 0; i != len; i++) {
                        superformIds[i] = cache.dstVaults[chainIndex][i];
                        amounts[i] = cache.sharesPerVault[chainIndex][i];
                        // Reduce vault debt individually
                        uint256 superformId = superformIds[i];
                        vaults[superformId].totalDebt -= vaults[superformId].convertToAssets(amounts[i]).toUint128();
                    }
                    uint256 withdrawn = _singleDirectMultiVaultWithdraw(superformIds, amounts, receiver);
                    cache.totalClaimableWithdraw += withdrawn;
                    cache.sharesFulfilled += convertToShares(withdrawn);
                    _totalIdle += withdrawn.toUint128();
                }
            }

            ////////////////////////////////////// REDEEM FROM OTHER CHAINS /////////////////////////////////////

            // Calculations to pick best withdraw type
            bool isSingleChain;
            bool isMultiChain;
            bool isMultiVault;
            for (uint256 i = 0; i != N_CHAINS; i++) {
                uint64 chainId = DST_CHAINS[i];
                // Skip the withdrawals in this chain[already happened]
                if (chainId == THIS_CHAIN_ID) {
                    continue;
                }
                uint256 chainIndex = chainIndexes[chainId];
                uint256 numberOfVaults = cache.lens[chainIndex];
                if (numberOfVaults == 0) {
                    continue;
                } else {
                    if (!isSingleChain) {
                        isSingleChain = true;
                    }

                    if (isSingleChain && !isMultiChain) {
                        isMultiChain = true;
                    }

                    if (numberOfVaults > 1) {
                        isMultiVault = true;
                    }
                }
            }

            // if(!isMultiChain) {
            //     if(!isMultiVault) {
            //         SingleXChainSingleVaultStateReq memory params = SingleXChainSingleVaultStateReq({
            //             // TODO: emptyAmbIds
            //             ambIds,
            //             dastChainId: THIS_CHAIN_ID,
            //             superformData: SingleVaultSFData({
            //                     superformId: superformId,
            //                     amount: sharesToRedeem,
            //                     outputAmount: 0,
            //                     maxSlippage: 0,
            //                     liqRequest: _getDefaultLiqRequest(),
            //                     permit2data: _getEmptyBytes(),
            //                     hasDstSwap: false,
            //                     retain4626: false,
            //                     receiverAddress: receiver,
            //                     receiverAddressSP: address(0),
            //                     extraFormData: _getEmptyBytes()
            //                 })
            //         });
            //         _vaultRouter.singleXChainMultiVaultWithdraw();
            //     }
            //     else {
            //         SingleXChainMultiVaultStateReq memory params = SingleXChainMultiVaultStateReq({
            //             ambIds,
            //             dastChainId: THIS_CHAIN_ID,
            //             superformData: MultiVaultSFData({
            //                 superformIds: superformIds,
            //                 amounts: amounts,
            //                 outputAmounts: emptyUint256Array,
            //                 maxSlippages: emptyUint256Array,
            //                 liqRequests: _getDefaultLiqRequestsArray(len),
            //                 permit2data: _getEmptyBytes(),
            //                 hasDstSwaps: emptyBoolArray,
            //                 retain4626s: emptyBoolArray,
            //                 receiverAddress: receiver,
            //                 receiverAddressSP: address(0),
            //                 extraFormData: _getEmptyBytes()
            //             })
            //         );
            //         _vaultRouter.singleXChainMultiVaultWithdraw(params);
            //     }
            // }
            // else {
            //     if(!isMultiVault) {
            //         MultiDstSingleVaultStateReq memory params = MultiDstSingleVaultStateReq({
            //             ambIds,
            //             dstChainIds,
            //             // TODO: ARRAY
            //             superformData: SingleVaultSFData({
            //                     superformId: superformId,
            //                     amount: sharesToRedeem,
            //                     outputAmount: 0,
            //                     maxSlippage: 0,
            //                     liqRequest: _getDefaultLiqRequest(),
            //                     permit2data: _getEmptyBytes(),
            //                     hasDstSwap: false,
            //                     retain4626: false,
            //                     receiverAddress: receiver,
            //                     receiverAddressSP: address(0),
            //                     extraFormData: _getEmptyBytes()
            //                 })
            //         });
            //         _vaultRouter.multiDstSingleVaultWithdraw();
            //     }
            //     else {
            //         MultiDstMultiVaultStateReq memory params = MultiDstMultiVaultStateReq({
            //             ambIds,
            //             dstChainIds,
            //             // TODO: ARRAY
            //             superformsData : MultiVaultSFData({
            //                 MultiVaultSFData({
            //                     superformIds: superformIds,
            //                     amounts: amounts,
            //                     outputAmounts: emptyUint256Array,
            //                     maxSlippages: emptyUint256Array,
            //                     liqRequests: _getDefaultLiqRequestsArray(len),
            //                     permit2data: _getEmptyBytes(),
            //                     hasDstSwaps: emptyBoolArray,
            //                     retain4626s: emptyBoolArray,
            //                     receiverAddress: receiver,
            //                     receiverAddressSP: address(0),
            //                     extraFormData: _getEmptyBytes()
            //                 })
            //             })
            //         });
            //         _vaultRouter.multiDstMultiVaultWithdraw();
            //     }
            // }
        }

        // EFECTS
        _totalAssets -= cache.totalClaimableWithdraw.toUint128();
        _totalIdle -= cache.totalClaimableWithdraw.toUint128();
        if (retainAssets) {
            _fulfillRedeemRequest(cache.sharesFulfilled, cache.totalClaimableWithdraw, controller);
        } else {
            _burn(owner, cache.sharesFulfilled);
            asset().safeTransfer(receiver, cache.totalClaimableWithdraw);
        }
    }

    // TODO: receive oracle call here using layer zero or something
    function report(VaultReport[] calldata reports) external onlyRoles(ORACLE_ROLE) {
        for (uint256 i = 0; i < reports.length; i++) {
            // Cache report
            VaultReport memory _report = reports[i];
            // Cache vault
            VaultData memory vault = vaults[_report.superformId];
            // Cache vault shares
            uint256 sharesBalance = _superPositions.balanceOf(address(this), vault.superformId);
            // Calculate totalAssets before the report
            uint256 totalAssetsBefore = vault.convertToAssets(sharesBalance);
            vaults[_report.superformId].sharePrice = _report.sharePrice;
            // Calculate totalAssets after the report
            uint256 totalAssetsAfter = vault.convertToAssets(sharesBalance);
            // Calculat the profit/loss
            int256 totalAssetsDelta = int256(totalAssetsAfter) - int256(totalAssetsBefore);

            // If there is profit assess management fees and add gains to vault
            if (totalAssetsDelta > 0) {
                uint256 gain = uint256(totalAssetsDelta);
                _assessFees(gain);
                _totalAssets += gain.toUint128();
            }
            // Else reduce total assets
            else {
                _totalAssets -= uint256(-totalAssetsDelta).toUint128();
            }
        }
    }

    /// @notice Applies fees to vault gains
    /// @notice Mints shares to the treasury
    /// @param gain The gain reported by the oracle
    function _assessFees(uint256 gain) private {
        // Apply fees
        uint256 managementFees = uint256(gain) * managementFee / MAX_BPS;
        // Mint fees shares to treasury
        uint256 sharesToMint = convertToShares(managementFees);
        _mint(treasury, sharesToMint);
    }

    function addVault(
        uint64 chainId,
        uint256 superformId,
        uint128 debtRatio,
        address vault,
        uint8 vaultDecimals
    )
        external
        onlyRoles(ADMIN_ROLE)
    {
        if (vaults[superformId].vaultAddress == address(0)) revert();
        if (_totalDebt / (_totalDebt + _totalIdle) + debtRatio > MAX_BPS) {
            revert();
        }
        if (!_factory.isSuperform(superformId)) revert();
        vaults[superformId].chainId = chainId;
        vaults[superformId].superformId = superformId;
        vaults[superformId].debtRatio = debtRatio;
        vaults[superformId].vaultAddress = vault;
        vaults[superformId].decimals = vaultDecimals;

        uint256[WITHDRAWAL_QUEUE_SIZE] memory queue = withdrawalQueue;
        for (uint256 i = 0; i != WITHDRAWAL_QUEUE_SIZE; i++) {
            if (queue[i] == 0) {
                withdrawalQueue[i] = superformId;
                break;
            }
        }
    }

    function updateVaultData(uint256 superformId, uint128 debtRatio) external onlyRoles(ADMIN_ROLE) {
        if (vaults[superformId].vaultAddress == address(0)) revert();
        vaults[superformId].debtRatio = debtRatio;
        if (_totalDebt / (_totalDebt + _totalIdle) + debtRatio > MAX_BPS) {
            revert();
        }
    }

    function setOracle(uint16 chain, address oracle) external onlyRoles(ADMIN_ROLE) {
        oracles[chain] = oracle;
    }

    function setManagementFee(uint16 _managementFee) external onlyRoles(ADMIN_ROLE) {
        managementFee = _managementFee;
    }

    function setAutopilot(bool set) external onlyRoles(ADMIN_ROLE) {
        autoPilot = set;
    }

    /// @dev Hook that is called after any deposit or mint.
    function _afterDeposit(uint256 assets, uint256 /*uint256 shares*/ ) internal override {
        uint128 castedAssets = assets.toUint128();
        _totalIdle += castedAssets;
        _totalAssets += castedAssets;
    }

    /// @dev Get a default liquidity request
    /// @return request the LiqRequest struct
    function _getDefaultLiqRequest() internal view returns (LiqRequest memory request) {
        return LiqRequest({
            txData: _getEmptyBytes(),
            token: _asset,
            interimToken: address(0),
            bridgeId: 1,
            liqDstChainId: THIS_CHAIN_ID,
            nativeAmount: 0
        });
    }

    function _getDefaultLiqRequestsArray(uint256 len) internal view returns (LiqRequest[] memory) {
        LiqRequest[] memory arr = new LiqRequest[](len);
        for (uint256 i = 0; i != len; ++i) {
            arr[i] = LiqRequest({
                txData: _getEmptyBytes(),
                token: _asset,
                interimToken: address(0),
                bridgeId: 1,
                liqDstChainId: THIS_CHAIN_ID,
                nativeAmount: 0
            });
        }
        return arr;
    }

    function _getEmptyBytes() internal pure returns (bytes memory) {
        return new bytes(0);
    }

    /// @dev Private helper to substract a - b or return 0 if it underflows
    function _sub0(uint256 a, uint256 b) internal pure virtual returns (uint256) {
        unchecked {
            return a - b > a ? 0 : a - b;
        }
    }

    /// @dev Private helper get an array uint256 full of zeros
    /// @param len array length
    /// @return
    function _getEmptyUint256Array(uint256 len) internal pure returns (uint256[] memory) {
        return new uint256[](len);
    }

    function _getEmptyBoolArray(uint256 len) internal pure returns (bool[] memory) {
        return new bool[](len);
    }

    function _singleDirectSingleVaultWithdraw(
        uint256 superformId,
        uint256 amount,
        address receiver
    )
        internal
        returns (uint256 withdrawn)
    {
        // Request
        SingleDirectSingleVaultStateReq memory params = SingleDirectSingleVaultStateReq({
            superformData: SingleVaultSFData({
                superformId: superformId,
                amount: amount,
                outputAmount: 0,
                maxSlippage: 0,
                liqRequest: _getDefaultLiqRequest(),
                permit2data: _getEmptyBytes(),
                hasDstSwap: false,
                retain4626: false,
                receiverAddress: receiver,
                receiverAddressSP: address(0),
                extraFormData: _getEmptyBytes()
            })
        });
        uint256 balanceBefore = asset().balanceOf(address(this));
        _vaultRouter.singleDirectSingleVaultWithdraw(params);
        return asset().balanceOf(address(this)) - balanceBefore;
    }

    function _singleDirectMultiVaultWithdraw(
        uint256[] memory superformIds,
        uint256[] memory amounts,
        address receiver
    )
        internal
        returns (uint256 withdrawn)
    {
        uint256 len = superformIds.length;
        uint256[] memory emptyUint256Array = _getEmptyUint256Array(len);
        bool[] memory emptyBoolArray = _getEmptyBoolArray(len);
        SingleDirectMultiVaultStateReq memory params = SingleDirectMultiVaultStateReq({
            superformData: MultiVaultSFData({
                superformIds: superformIds,
                amounts: amounts,
                outputAmounts: emptyUint256Array,
                maxSlippages: emptyUint256Array,
                liqRequests: _getDefaultLiqRequestsArray(len),
                permit2data: _getEmptyBytes(),
                hasDstSwaps: emptyBoolArray,
                retain4626s: emptyBoolArray,
                receiverAddress: receiver,
                receiverAddressSP: address(0),
                extraFormData: _getEmptyBytes()
            })
        });
        uint256 balanceBefore = asset().balanceOf(address(this));
        _vaultRouter.singleDirectMultiVaultWithdraw(params);
        return asset().balanceOf(address(this)) - balanceBefore;
    }
}
