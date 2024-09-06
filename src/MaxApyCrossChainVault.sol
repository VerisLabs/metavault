/// SPDX-License-Identifer: MIT
pragma solidity 0.8.21;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { ERC7540, ReentrancyGuard } from "./lib/Lib.sol";
import { ISuperPositions, IBaseRouter, ISuperformFactory } from "./interfaces/Lib.sol";
import "./types/Lib.sol";

/// @title MaxApyCrossChainVault
/// @author Unlockd
/// notice description
contract MaxApyCrossChainVault is ERC7540, OwnableRoles, ReentrancyGuard {
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

    /// @notice maps the assets and data of each allocated vault
    mapping(address vaultAddress => VaultData) public vaults;
    /// @notice the ERC4626 oracle of each chain
    mapping(uint16 chain => address) public oracles;
    /// @notice Maximum number of vaults the vault can invest in
    address[WITHDRAWAL_QUEUE_SIZE] public withdrawalQueue;
    /// @notice Cached value of total assets managed by the vault
    uint256 private _totalAssets;
    /// @notice Underlying asset
    address private immutable _asset;
    /// @notice ERC20 name
    string private _name;
    /// @notice ERC20 symbol
    string private _symbol;
    /// @notice Cached value of total assets in this vault
    uint256 private _totalIdle;
    /// @notice Cached value of total allocated assets
    uint256 private _totalDebt;
    /// @notice Protocol fee
    uint256 managementFee;
    /// @notice Fee receiver
    address treasury;
    /// @notice Superform ERC1155 Superpositions
    ISuperPositions superPositions;
    /// @notice Superform Router
    IBaseRouter vaultRouter;
    /// @notice Superform Factory to validate superforms
    ISuperformFactory factory;
    /// @notice Wether the vault is paused
    bool emergencyShutdown;
    /// @notice AutoPilot
    bool autoPilot;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           MODIFIERS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier noEmergencyShutdown() {
        if (emergencyShutdown) {
            revert();
        }
        _;
    }

    constructor(address _asset_, string memory _name_, string memory _symbol_) {
        _asset = _asset_;
        _name = _name_;
        _symbol = _symbol_;
        for (uint256 i = 0; i != N_CHAINS; i++) {
            chainIndexes[DST_CHAINS[i]] = i;
        }
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
        shares = super.deposit(assets, to, controller);
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
        assets = super.mint(shares, to, controller);
        _afterDeposit(assets, shares);
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
        requestId = super.requestRedeem(shares, controller, owner);
        if (autoPilot) {
            fulfillRedeemRequest(controller, shares);
        }
    }

    /// @dev returns the total assets held by the vault
    function totalAssets() public view override returns (uint256 assets) {
        return _totalAssets;
    }

    // TODO: loop through the vaults to move the money
    function invest() external onlyRoles(INVESTOR_ROLE) {
        for (uint256 i = 0; i < WITHDRAWAL_QUEUE_SIZE; i++) { }
    }

    function fulfillRedeemRequest(address user, uint256 shares) public {
        // cache totalIdle
        uint256 totalIdle = _totalIdle;
        // convert shares to assets at current price
        uint256 assets = convertToAssets(shares);
        // If totalIdles can covert the amount fulfill directly
        if (totalIdle >= assets) {
            _fulfillRedeemRequest(user, shares, assets);
        }
        // Otherwise perform Superform withdrawals
        else {
            // List of vauts to withdraw from on each chain
            uint256[WITHDRAWAL_QUEUE_SIZE][N_CHAINS] memory dstVaults;
            // List of shares to redeem on each vault in each chain
            uint256[WITHDRAWAL_QUEUE_SIZE][N_CHAINS] memory sharesPerVault;
            // Cache length of list of each chain
            uint256[N_CHAINS] memory lens;
            // Cache amount to withdraw before reducing totalIdle
            uint256 amountToWithdraw = assets - _totalIdle;
            // Use totalIdle to fulfillTheRequset
            if (totalIdle > 0) {
                // TODO: round up?
                _fulfillRedeemRequest(user, convertToShares(totalIdle), totalIdle);
            }
            /////////////////////////////////PREVIOUS CALCULATIONS ///////////////////////////////////////
            // Cache how many chains we need and how many vaults in each chain
            for (uint256 i = 0; i != WITHDRAWAL_QUEUE_SIZE; i++) {
                // If its fulfilled stop
                if (amountToWithdraw == 0) break;
                // Cache next vault from the withdrawal queue
                VaultData memory vault = vaults[withdrawalQueue[i]];
                // Calcualate the maxWithdraw of the vault
                uint256 maxWithdraw = vault.convertToAssets(superPositions.balanceOf(address(this), vault.superformId));
                // Dont withdraw more than max
                uint256 assets = Math.min(maxWithdraw, amountToWithdraw);
                // Cache chain index
                uint256 chainIndex = chainIndexes[vault.chainId];
                // Cache chain lenght
                uint256 len = lens[chainIndex];
                dstVaults[chainIndex][len] = vault.superformId;
                sharesPerVault[chainIndex][len] = vault.convertToShares(assets);
                amountToWithdraw -= assets;
                unchecked {
                    lens[chainIndex]++;
                }
            }
            uint256 currentChainIndex = chainIndexes[THIS_CHAIN_ID];
            ////////////////////////////////////// REDEEM FROM THIS CHAIN /////////////////////////////////////
            // implement redeem logic
            if (dstVaults[currentChainIndex].length > 0) {
                uint256 withdrawn;
                uint256 sharesFulfilled;
                uint256[WITHDRAWAL_QUEUE_SIZE] memory _superformIds = dstVaults[THIS_CHAIN_ID];
                // Cache chain index
                uint256 chainIndex = chainIndexes[THIS_CHAIN_ID];
                // TODO: cant check lenghts like this, its fixed array
                if (_superformIds.length == 1) {
                    sharesFulfilled = sharesPerVault[chainIndex][0];
                    uint256 superformId = dstVaults[chainIndex][0];
                    SingleDirectSingleVaultStateReq memory params = SingleDirectSingleVaultStateReq({
                        superformData: SingleVaultSFData({
                            superformId: superformId,
                            amount: sharesFulfilled,
                            outputAmount: 0,
                            maxSlippage: 0,
                            liqRequest: _getDefaultLiqRequest(),
                            permit2data: _getEmptyBytes(),
                            hasDstSwap: false,
                            retain4626: false,
                            receiverAddress: address(this),
                            receiverAddressSP: address(0),
                            extraFormData: _getEmptyBytes()
                        })
                    });
                    uint256 withdrawn = _singleDirectSingleVaultWithdraw(params);
                } else {
                    uint256 len = lens[chainIndex];
                    uint256[] memory superformIds = new uint256[](len);
                    uint256[] memory amounts = new uint256[](len);
                    uint256[] memory emptyUint256Array = _getEmptyUint256Array(len);
                    bool[] memory emptyBoolArray = _getEmptyBoolArray(len);
                    uint256[WITHDRAWAL_QUEUE_SIZE] memory _superformIds = dstVaults[chainIndex];
                    uint256[WITHDRAWAL_QUEUE_SIZE] memory _amounts = sharesPerVault[chainIndex];
                    for (uint256 i = 0; i != len; i++) {
                        superformIds[i] = _superformIds[i];
                        sharesFulfilled += _amounts[i];
                        amounts[i] = _amounts[i];
                    }
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
                            receiverAddress: address(this),
                            receiverAddressSP: address(0),
                            extraFormData: _getEmptyBytes()
                        })
                    });
                    withdrawn = _singleDirectMultiVaultWithdraw(params);
                }
                _totalIdle += withdrawn;
                _fulfillRedeemRequest(user, sharesFulfilled, withdrawn);
            }
            ////////////////////////////////////// REDEEM FROM OTHER CHAINS /////////////////////////////////////

            // Calculations to pick best withdraw type
            bool isSingleChain;
            bool isMultiChain;
            bool isMultiVault;
            for (uint256 i = 0; i != N_CHAINS; i++) {
                uint256[WITHDRAWAL_QUEUE_SIZE] memory _superformIds = dstVaults[THIS_CHAIN_ID];
                uint64 chainId = DST_CHAINS[i];
                if (chainId == THIS_CHAIN_ID) {
                    continue;
                }
                uint256 chainIndex = chainIndexes[chainId];
                uint256 numberOfVaults = lens[chainIndex];
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
            //                     receiverAddress: address(this),
            //                     receiverAddressSP: address(0),
            //                     extraFormData: _getEmptyBytes()
            //                 })
            //         });
            //         vaultRouter.singleXChainMultiVaultWithdraw();
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
            //                 receiverAddress: address(this),
            //                 receiverAddressSP: address(0),
            //                 extraFormData: _getEmptyBytes()
            //             })
            //         );
            //         vaultRouter.singleXChainMultiVaultWithdraw(params);
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
            //                     receiverAddress: address(this),
            //                     receiverAddressSP: address(0),
            //                     extraFormData: _getEmptyBytes()
            //                 })
            //         });
            //         vaultRouter.multiDstSingleVaultWithdraw();
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
            //                     receiverAddress: address(this),
            //                     receiverAddressSP: address(0),
            //                     extraFormData: _getEmptyBytes()
            //                 })
            //             })
            //         });
            //         vaultRouter.multiDstMultiVaultWithdraw();
            //     }
            // }
        }
    }

    /// @dev Hook that is called when processing a redeem request and make it claimable.
    function _fulfillRedeemRequest(
        address controller,
        uint256 sharesFulfilled,
        uint256 assetsWithdrawn
    )
        internal
        override
    {
        super._fulfillRedeemRequest(controller, sharesFulfilled, assetsWithdrawn);
        _totalIdle -= assetsWithdrawn;
        _totalAssets -= assetsWithdrawn;
    }

    // TODO: receive oracle call here
    function report(VaultReport[] calldata reports) external onlyRoles(ORACLE_ROLE) {
        // for (uint256 i = 0; i < reports.length; i++) {
        //     VaultReport memory _report = reports[i];
        //     VaultData memory data = vaults[_report.vault];
        //     int256 sharePriceDelta = int256(_report.sharePrice) - int256(data.sharePrice);

        //     if (sharePriceDelta > 0) {
        //         _totalAssets += uint256(totalAssetsDelta);
        //     } else {
        //         _totalAssets -= uint256(-totalAssetsDelta);
        //     }

        //     vaults[_report.vault].totalAssets = _report.totalAssets;
        //     vaults[_report.vault].totalAssets = _report.totalAssets;
        // }
    }

    // TODO: add vault to withdrawal queue
    function addVault(
        uint64 chainId,
        uint256 superformId,
        uint256 debtRatio,
        address vault,
        uint256 vaultDecimals
    )
        external
    {
        if (vaults[vault].vaultAddress == address(0)) revert();
        if (_totalDebt / (_totalDebt + _totalIdle) + debtRatio > MAX_BPS) {
            revert();
        }
        if (!factory.isSuperform(superformId)) revert();
        vaults[vault].chainId = chainId;
        vaults[vault].superformId = superformId;
        vaults[vault].debtRatio = debtRatio;
        vaults[vault].vaultAddress = vault;
        vaults[vault].decimals = vaultDecimals;

        address[WITHDRAWAL_QUEUE_SIZE] memory queue = withdrawalQueue;
        for (uint256 i = 0; i != WITHDRAWAL_QUEUE_SIZE; i++) {
            if (queue[i] == address(0)) {
                withdrawalQueue[i] = vault;
                break;
            }
        }
    }

    // TODO: update vault allocation
    function updateVaultData(address vault, uint256 debtRatio) external {
        if (vaults[vault].vaultAddress == address(0)) revert();
        vaults[vault].debtRatio = debtRatio;
        if (_totalDebt / (_totalDebt + _totalIdle) + debtRatio > MAX_BPS) {
            revert();
        }
    }

    // TODO: set the oracle for a chain
    function setOracle(uint16 chain, address oracle) external onlyRoles(ADMIN_ROLE) {
        oracles[chain] = oracle;
    }

    /// @dev Hook that is called after any deposit or mint.
    function _afterDeposit(uint256 assets, uint256 /*uint256 shares*/ ) internal override {
        _totalIdle += assets;
        _totalAssets += assets;
    }

    function _getDefaultLiqRequest() internal view returns (LiqRequest memory) {
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

    function _getEmptyUint256Array(uint256 len) internal pure returns (uint256[] memory) {
        return new uint256[](len);
    }

    function _getEmptyBoolArray(uint256 len) internal pure returns (bool[] memory) {
        return new bool[](len);
    }

    function _singleDirectSingleVaultWithdraw(SingleDirectSingleVaultStateReq memory params)
        internal
        returns (uint256 withdrawn)
    {
        uint256 balanceBefore = asset().balanceOf(address(this));
        vaultRouter.singleDirectSingleVaultWithdraw(params);
        return asset().balanceOf(address(this)) - balanceBefore;
    }

    function _singleDirectMultiVaultWithdraw(SingleDirectMultiVaultStateReq memory params)
        internal
        returns (uint256 withdrawn)
    {
        uint256 balanceBefore = asset().balanceOf(address(this));
        vaultRouter.singleDirectMultiVaultWithdraw(params);
        return asset().balanceOf(address(this)) - balanceBefore;
    }
}
