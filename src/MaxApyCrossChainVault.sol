/// SPDX-License-Identifer: MIT
pragma solidity 0.8.19;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { ERC7540, ReentrancyGuard } from "lib/Lib.sol";
import { ISuperPositions, IBaseRouter, ISuperformFactory } from "interfaces/Lib.sol";
import { ERC20Receiver } from "crosschain/Lib.sol";
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
    SingleDirectMultiVaultStateReq
} from "types/Lib.sol";

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
    uint256 public constant SECS_PER_YEAR = 31_556_952;
    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant EMERGENCY_ADMIN_ROLE = _ROLE_1;
    uint256 public constant ORACLE_ROLE = _ROLE_2;
    uint256 public constant MANAGER_ROLE = _ROLE_3;
    uint256 public constant RELAYER_ROLE = _ROLE_4;
    uint24 public constant REQUEST_REDEEM_DELAY = 1 days;
    uint64 public immutable THIS_CHAIN_ID;
    uint256 public constant N_CHAINS = 7;
    uint64[N_CHAINS] public DST_CHAINS = [
        1, // Ethereum Mainnet
        137, // Polygon
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
    /// @notice Maximum number of vaults the vault can invest in
    uint256[WITHDRAWAL_QUEUE_SIZE] public withdrawalQueue;
    /// @notice Timestamp of deposit lock
    mapping(address => uint256) depositLockCheckPoint;
    /// @notice Receiver delegation for withdrawals
    mapping(address => address) private _receivers;
    /// @notice Implementation contract of the receiver contract
    address public receiverImplementation;
    /// @notice Timestamp of deposit lock
    mapping(address => uint256) private _requestRedeemLockCheckPoint;
    /// @notice Default config for redeem requests
    uint8[] public defaultAmbIds;
    /// @notice Inverse mapping vault => superformId
    mapping(address => uint256) _vaultToSuperformId;
    uint256 public lastReport;
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
        uint24 _sharesLockTime,
        ISuperPositions _superPositions_,
        IBaseRouter _vaultRouter_,
        ISuperformFactory _factory_
    ) {
        _asset = _asset_;
        _name = _name_;
        _symbol = _symbol_;
        managementFee = _managementFee;
        sharesLockTime = _sharesLockTime;
        _factory = _factory_;
        _superPositions = _superPositions_;
        _vaultRouter = _vaultRouter_;
        (bool success, uint8 result) = _tryGetAssetDecimals(_asset_);
        _decimals = success ? result : _DEFAULT_UNDERLYING_DECIMALS;
        THIS_CHAIN_ID = uint64(block.chainid);
        for (uint256 i = 0; i != N_CHAINS; i++) {
            chainIndexes[DST_CHAINS[i]] = i;
        }
        _initializeOwner(msg.sender);
        _grantRoles(msg.sender, ADMIN_ROLE);
        receiverImplementation = address(new ERC20Receiver(_asset_));
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
            depositLockCheckPoint[to] = block.timestamp;
        } else {
            depositLockCheckPoint[to] =
                (depositLockCheckPoint[to] * sharesBalance / newBalance) + (block.timestamp * newShares / newBalance);
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
            _processRedeemRequest(shares, controller, owner, _receiver(controller), true);
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
        ERC20Receiver receiverContract = ERC20Receiver(_receiver(controller));
        uint256 claimableXChain = receiverContract.balance();
        receiverContract.pull(claimableXChain);
        _fulfillRedeemRequest(pendingRedeemRequest(controller), claimableXChain, controller);
        return super.redeem(shares, receiver, controller);
    }

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
        ERC20Receiver receiverContract = ERC20Receiver(_receiver(controller));
        uint256 claimableXChain = receiverContract.balance();
        receiverContract.pull(claimableXChain);
        _fulfillRedeemRequest(pendingRedeemRequest(controller), claimableXChain, controller);
        return super.withdraw(assets, receiver, controller);
    }

    function _checkSharesLocked(address owner) private view {
        if (block.timestamp < depositLockCheckPoint[owner] + sharesLockTime) revert();
    }

    function redeemAtomic(uint256 shares, address controller, address owner, address receiver) public nonReentrant {
        _checkSharesLocked(controller);
        _processRedeemRequest(shares, controller, owner, receiver, false);
    }

    function processRedeemRequest(uint256 shares, address controller) external onlyRoles(RELAYER_ROLE) {
        _processRedeemRequest(shares, controller, controller, address(this), true);
    }

    function investSingleDirectSingleVault(
        address vaultAddress,
        uint256 amount,
        uint256 minAmountOut
    )
        public
        onlyRoles(MANAGER_ROLE)
    {
        if (!isVaultListed(vaultAddress)) revert();
        uint256 balanceBefore = vaultAddress.balanceOf(address(this));
        ERC4626(vaultAddress).deposit(amount, address(this));
        uint256 minted = vaultAddress.balanceOf(address(this)) - balanceBefore;
        if (minted < minAmountOut) {
            revert();
        }
        uint128 amountUint128 = amount.toUint128();
        _totalIdle -= amountUint128;
        _totalDebt += amountUint128;
        vaults[_vaultToSuperformId[vaultAddress]].totalDebt += amountUint128;
    }

    function totalIdle() public view returns (uint256) {
        return _totalIdle;
    }

    function totalDebt() public view returns (uint256) {
        return _totalDebt;
    }

    function investSingleDirectMultiVault(
        address[] calldata vaultAddresses,
        uint256[] calldata amounts,
        uint256[] calldata minAmountOuts
    )
        external
    {
        for (uint256 i = 0; i < vaultAddresses.length; ++i) {
            investSingleDirectSingleVault(vaultAddresses[i], amounts[i], minAmountOuts[i]);
        }
    }

    function investSingleXChainSingleVault() external onlyRoles(MANAGER_ROLE) { }

    function investSingleXChainMultiVault() external onlyRoles(MANAGER_ROLE) { }

    function investMultiXChainSingleVault() external onlyRoles(MANAGER_ROLE) { }

    function investMultiXChainMultiVault() external onlyRoles(MANAGER_ROLE) { }

    function _prepareWithdrawalRoute(ProcessRedeemRequestCache memory cache) internal view {
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
            uint256 maxWithdraw = vault.convertToAssets(_sharesBalance(vault));
            // Dont withdraw more than max
            uint256 withdrawAssets = Math.min(maxWithdraw, cache.amountToWithdraw);
            if (withdrawAssets == 0) continue;
            // Cache chain index
            uint256 chainIndex = chainIndexes[vault.chainId];
            // Cache chain length
            uint256 len = cache.lens[chainIndex];
            // Push the superformId to the last index of the array
            cache.dstVaults[chainIndex][len] = vault.superformId;
            uint256 shares = vault.convertToShares(withdrawAssets);
            if (shares == 0) continue;
            // Push the shares to redeeem of that vault
            cache.sharesPerVault[chainIndex][len] = shares;
            // Reduce needed assets
            cache.amountToWithdraw -= withdrawAssets;

            // Cache wether is single chain or multichain
            if (vault.chainId != THIS_CHAIN_ID) {
                uint256 numberOfVaults = cache.lens[chainIndex];
                if (numberOfVaults == 0) {
                    continue;
                } else {
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

    struct ProcessRedeemRequestCache {
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
        // Cache totalIdle
        uint256 totalIdle;
        // Convert shares to assets at current price
        uint256 assets;
        // Wether is a single chain or multichain withdrawal
        bool isSingleChain;
        bool isMultiChain;
        // Wether is a single or multivault withdrawal
        bool isMultiVault;
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
        ProcessRedeemRequestCache memory cache;
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
            _prepareWithdrawalRoute(cache);
            ////////////////////////////////////// REDEEM FROM THIS CHAIN /////////////////////////////////////
            // Cache chain index
            uint256 chainIndex = chainIndexes[THIS_CHAIN_ID];
            if (cache.lens[chainIndex] > 0) {
                address directWithdrawalReceiver = retainAssets ? address(this) : receiver;
                if (cache.lens[chainIndex] == 1) {
                    // shares to redeem
                    uint256 sharesAmount = cache.sharesPerVault[chainIndex][0];
                    // superformId(take first element fo the array)
                    uint256 superformId = cache.dstVaults[chainIndex][0];
                    // get actual withdrawn amount
                    uint256 withdrawn = _singleDirectSingleVaultWithdraw(
                        vaults[superformId].vaultAddress, sharesAmount, 0, directWithdrawalReceiver
                    );
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
                    address[] memory vaultAddresses = new address[](len);
                    uint256[] memory amounts = new uint256[](len);
                    // Cast fixed arrays to dynamic ones
                    for (uint256 i = 0; i != len; i++) {
                        vaultAddresses[i] = vaults[cache.dstVaults[chainIndex][i]].vaultAddress;
                        amounts[i] = cache.sharesPerVault[chainIndex][i];
                        // Reduce vault debt individually
                        uint256 superformId = cache.dstVaults[chainIndex][i];
                        vaults[superformId].totalDebt -= vaults[superformId].convertToAssets(amounts[i]).toUint128();
                    }
                    uint256 withdrawn = _singleDirectMultiVaultWithdraw(
                        vaultAddresses, amounts, _getEmptyUint256Array(amounts.length), directWithdrawalReceiver
                    );
                    cache.totalClaimableWithdraw += withdrawn;
                    cache.sharesFulfilled += convertToShares(withdrawn);
                    _totalIdle += withdrawn.toUint128();
                }
            }

            ////////////////////////////////////// REDEEM FROM EXTERNAL CHAINS /////////////////////////////////////
            if (!cache.isMultiChain) {
                if (!cache.isMultiVault) {
                    uint256 superformId;
                    uint256 amount;
                    uint64 chainId;

                    for (uint256 i = 0; i < cache.dstVaults.length; ++i) {
                        if (DST_CHAINS[i] == THIS_CHAIN_ID) continue;
                        if (cache.lens[i] > 0) {
                            chainId = DST_CHAINS[i];
                            superformId = cache.dstVaults[i][0];
                            amount = cache.sharesPerVault[i][0];
                            _singleXChainSingleVaultWithdraw(chainId, superformId, amount, receiver);
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
                            _singleXChainMultiVaultWithdraw(chainId, superformIds, amounts, receiver);
                            break;
                        }
                    }
                }
            } else {
                if (!cache.isMultiVault) {
                    uint256 chainsLen;
                    for (uint256 i = 0; i < cache.lens.length; i++) {
                        if (cache.lens[i] > 0) chainsLen++;
                    }
                    uint8[] memory _defaultAmbIds = _getDefaultAmbIds();
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
                            outputAmount: 0,
                            maxSlippage: 0,
                            liqRequest: _getDefaultLiqRequest(),
                            permit2data: _getEmptyBytes(),
                            hasDstSwap: false,
                            retain4626: false,
                            receiverAddress: receiver,
                            receiverAddressSP: address(0),
                            extraFormData: _getEmptyBytes()
                        });
                        ambIds[i] = _defaultAmbIds;
                    }
                    _multiDstSingleVaultWithdraw(ambIds, dstChainIds, singleVaultDatas);
                } else {
                    uint256 chainsLen;
                    for (uint256 i = 0; i < cache.lens.length; i++) {
                        if (cache.lens[i] > 0) chainsLen++;
                    }
                    uint8[] memory _defaultAmbIds = _getDefaultAmbIds();
                    uint8[][] memory ambIds = new uint8[][](chainsLen);
                    uint64[] memory dstChainIds = new uint64[](chainsLen);
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
                            outputAmounts: emptyUint256Array,
                            maxSlippages: emptyUint256Array,
                            liqRequests: _getDefaultLiqRequestsArray(cache.lens[i]),
                            permit2data: _getEmptyBytes(),
                            hasDstSwaps: emptyBoolArray,
                            retain4626s: emptyBoolArray,
                            receiverAddress: receiver,
                            receiverAddressSP: address(0),
                            extraFormData: _getEmptyBytes()
                        });
                        ambIds[i] = _defaultAmbIds;
                    }
                    _multiDstMultiVaultWithdraw(ambIds, dstChainIds, multiVaultDatas);
                }
            }
        }

        // EFECTS
        _totalAssets -= cache.totalClaimableWithdraw.toUint128();
        _totalIdle -= cache.totalClaimableWithdraw.toUint128();

        // INTERACTIONS
        if (retainAssets) {
            _burn(address(this), shares);
            _fulfillRedeemRequest(cache.sharesFulfilled, cache.totalClaimableWithdraw, controller);
        } else {
            _burn(owner, shares);
            asset().safeTransfer(receiver, cache.totalClaimableWithdraw);
        }
    }

    function report(VaultReport[] calldata reports) external onlyRoles(ORACLE_ROLE) {
        for (uint256 i = 0; i < reports.length; i++) {
            // Cache report
            VaultReport memory _report = reports[i];
            // Get superform id
            uint256 superformId = _vaultToSuperformId[_report.vaultAddress];
            // Cache vault
            VaultData memory vault = vaults[superformId];
            // Cache vault shares
            uint256 sharesBalance = _superPositions.balanceOf(address(this), vault.superformId);
            // Calculate totalAssets before the report
            uint256 totalAssetsBefore = vault.convertToAssets(sharesBalance);
            vaults[superformId].sharePrice = _report.sharePrice;
            // Calculate totalAssets after the report
            uint256 totalAssetsAfter = vault.convertToAssets(sharesBalance);
            // Calculat the profit/loss
            int256 totalAssetsDelta = int256(totalAssetsAfter) - int256(totalAssetsBefore);

            // If there is profit assess management fees and add gains to vault
            if (totalAssetsDelta > 0) {
                uint256 gain = uint256(totalAssetsDelta);
                _totalAssets += gain.toUint128();
            }
            // Else reduce total assets
            else {
                _totalAssets -= uint256(-totalAssetsDelta).toUint128();
            }
        }

        _assessFees();
    }

    /// @notice Applies fees to vault gains
    /// @notice Mints shares to the treasury
    function _assessFees() private {
        // Apply fees
        uint256 duration = block.timestamp - lastReport;
        uint256 managementFees = _totalAssets * duration * managementFee / SECS_PER_YEAR / MAX_BPS;
        // Mint fees shares to treasury
        uint256 sharesToMint = convertToShares(managementFees);
        _mint(treasury, sharesToMint);
    }

    function isVaultListed(address vaultAddress) public view returns (bool) {
        return _vaultToSuperformId[vaultAddress] != 0;
    }

    function addVault(
        uint64 chainId,
        uint256 superformId,
        address vault,
        uint8 vaultDecimals,
        uint192 sharePrice
    )
        external
        onlyRoles(ADMIN_ROLE)
    {
        if (vaults[superformId].vaultAddress != address(0)) revert();
        if (chainId != THIS_CHAIN_ID && !_factory.isSuperform(superformId)) {
            revert();
        }
        vaults[superformId].chainId = chainId;
        vaults[superformId].superformId = superformId;
        vaults[superformId].vaultAddress = vault;
        vaults[superformId].decimals = vaultDecimals;
        vaults[superformId].sharePrice = sharePrice;
        _vaultToSuperformId[vault] = superformId;

        uint256[WITHDRAWAL_QUEUE_SIZE] memory queue = withdrawalQueue;
        for (uint256 i = 0; i != WITHDRAWAL_QUEUE_SIZE; i++) {
            if (queue[i] == 0) {
                withdrawalQueue[i] = superformId;
                break;
            }
        }

        if (chainId == THIS_CHAIN_ID) {
            asset().safeApprove(vault, type(uint256).max);
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

    function setDefaultAmbIds(uint8[] memory _ambIds) external onlyRoles(ADMIN_ROLE) {
        defaultAmbIds = _ambIds;
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
        address vault,
        uint256 amount,
        uint256 minAmountOut,
        address receiver
    )
        internal
        returns (uint256 withdrawn)
    {
        uint256 balanceBefore = asset().balanceOf(address(this));
        ERC4626(vault).redeem(amount, address(this), receiver);
        withdrawn = asset().balanceOf(address(this)) - balanceBefore;
        if (withdrawn < minAmountOut) {
            revert();
        }
    }

    function _singleDirectMultiVaultWithdraw(
        address[] memory vaults,
        uint256[] memory amounts,
        uint256[] memory minAmountsOut,
        address receiver
    )
        internal
        returns (uint256 withdrawn)
    {
        for (uint256 i = 0; i < vaults.length; ++i) {
            withdrawn += _singleDirectSingleVaultWithdraw(vaults[i], amounts[i], minAmountsOut[i], receiver);
        }
    }

    function _singleDirectSingleVaultDeposit(uint256 superformId, uint256 amount, address receiver) internal {
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
        _vaultRouter.singleDirectSingleVaultDeposit(params);
    }

    function _singleDirectMultiVaultDeposit(
        uint256[] memory superformIds,
        uint256[] memory amounts,
        address receiver
    )
        internal
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
        _vaultRouter.singleDirectMultiVaultDeposit(params);
    }

    function _singleXChainSingleVaultWithdraw(
        uint64 chainId,
        uint256 superformId,
        uint256 amount,
        address receiver
    )
        internal
    {
        SingleXChainSingleVaultStateReq memory params = SingleXChainSingleVaultStateReq({
            ambIds: _getDefaultAmbIds(),
            dstChainId: chainId,
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
        _vaultRouter.singleXChainSingleVaultWithdraw(params);
    }

    function _singleXChainMultiVaultWithdraw(
        uint64 chainId,
        uint256[] memory superformIds,
        uint256[] memory amounts,
        address receiver
    )
        internal
    {
        uint256 len = superformIds.length;
        uint256[] memory emptyUint256Array = _getEmptyUint256Array(len);
        bool[] memory emptyBoolArray = _getEmptyBoolArray(len);
        SingleXChainMultiVaultStateReq memory params = SingleXChainMultiVaultStateReq({
            ambIds: _getDefaultAmbIds(),
            dstChainId: chainId,
            superformsData: MultiVaultSFData({
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
        _vaultRouter.singleXChainMultiVaultWithdraw(params);
    }

    function _multiDstSingleVaultWithdraw(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        SingleVaultSFData[] memory singleVaultDatas
    )
        internal
    {
        MultiDstSingleVaultStateReq memory params =
            MultiDstSingleVaultStateReq({ ambIds: ambIds, dstChainIds: dstChainIds, superformsData: singleVaultDatas });
        _vaultRouter.multiDstSingleVaultWithdraw(params);
    }

    function _multiDstMultiVaultWithdraw(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        MultiVaultSFData[] memory multiVaultDatas
    )
        private
    {
        MultiDstMultiVaultStateReq memory params =
            MultiDstMultiVaultStateReq({ ambIds: ambIds, dstChainIds: dstChainIds, superformsData: multiVaultDatas });
        _vaultRouter.multiDstMultiVaultWithdraw(params);
    }

    function _getDefaultAmbIds() private view returns (uint8[] memory) {
        return defaultAmbIds;
    }

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

    function _receiver(address owner) private returns (address receiverAddress) {
        address current = _receivers[owner];
        if (current != address(0)) {
            return current;
        } else {
            receiverAddress =
                LibClone.clone(receiverImplementation, abi.encodeWithSignature("initialize(address)", owner));
            _receivers[owner] = receiverAddress;
        }
    }

    function _sharesBalance(VaultData memory data) private view returns (uint256 shares) {
        if (data.chainId == THIS_CHAIN_ID) {
            return ERC4626(data.vaultAddress).balanceOf(address(this));
        } else {
            return _superPositions.balanceOf(address(this), data.superformId);
        }
    }
}
