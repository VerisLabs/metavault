/// SPDX-License-Identifer: MIT
pragma solidity 0.8.21;

import {ERC4626, OwnableRoles, FixedPointMathLib, VaultData, ISuperPositions, IBaseRouter, ISuperformFactory} from "./lib/Index.sol";

/// @title SuperVault
/// @author Unlockd
/// notice description
contract SuperVault is ERC4626, OwnableRoles {
    // CONSTANTS
    uint256 public constant WITHDRAWAL_QUEUE_SIZE = 30;
    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant EMERGENCY_ADMIN_ROLE = _ROLE_1;
    uint256 public constant ORACLE_ROLE = _ROLE_2;
    uint256 public constant INVESTOR_ROLE = _ROLE_3;

    // STORAGE
    mapping(address vaultAddress => VaultData) public vaults;
    mapping(uint16 chain => address) public oracles;
    address[WITHDRAWAL_QUEUE_SIZE] public withdrawalQueue;
    uint256 private _totalAssets;
    uint256 private _totalAssetsWithdrawable;
    address private immutable _asset;
    string private _name;
    string private _symbol;
    uint256 private _totalIdle;
    uint256 private _totalDebt;
    uint256 managementFee;
    address treasury;
    ISuperPositions superPositions;
    IBaseRouter vaultRouter;
    ISuperformFactory factory;

    constructor(address _asset_, string memory _name_, string memory _symbol_) {
        _asset = _asset_;
        _name = _name_;
        _symbol = _symbol_;
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

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their withdrawal
    /// at the current block, given the current on-chain conditions.
    ///
    /// - MUST return as close to and no fewer than the exact amount of Vault shares that
    ///   will be burned in a withdraw call in the same transaction, i.e. withdraw should
    ///   return the same or fewer shares as `previewWithdraw` if call in the same transaction.
    /// - MUST NOT account for withdrawal limits like those returned from `maxWithdraw` and should
    ///   always act as if the withdrawal will be accepted, regardless of share balance, etc.
    /// - MUST be inclusive of withdrawal fees. Integrators should be aware of this.
    /// - MUST not revert.
    ///
    /// Note: Any unfavorable discrepancy between `convertToShares` and `previewWithdraw` SHOULD
    /// be considered slippage in share price or some other type of condition,
    /// meaning the depositor will lose assets by depositing.
    function previewWithdraw(
        uint256 assets
    ) public view override returns (uint256 shares) {
        if (!_useVirtualShares()) {
            uint256 supply = totalSupply();
            return
                _eitherIsZero_(assets, supply)
                    ? _initialConvertToShares(assets)
                    : FixedPointMathLib.fullMulDivUp(
                        assets,
                        supply,
                        totalAssetsWithdrawable()
                    );
        }
        uint256 o = _decimalsOffset();
        if (o == uint256(0)) {
            return
                FixedPointMathLib.fullMulDivUp(
                    assets,
                    totalSupply() + 1,
                    _inc_(totalAssetsWithdrawable())
                );
        }
        return
            FixedPointMathLib.fullMulDivUp(
                assets,
                totalSupply() + 10 ** o,
                _inc_(totalAssetsWithdrawable())
            );
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their redemption
    /// at the current block, given current on-chain conditions.
    ///
    /// - MUST return as close to and no more than the exact amount of assets that
    ///   will be withdrawn in a redeem call in the same transaction, i.e. redeem should
    ///   return the same or more assets as `previewRedeem` if called in the same transaction.
    /// - MUST NOT account for redemption limits like those returned from `maxRedeem` and should
    ///   always act as if the redemption will be accepted, regardless of approvals, etc.
    /// - MUST be inclusive of withdrawal fees. Integrators should be aware of this.
    /// - MUST NOT revert.
    ///
    /// Note: Any unfavorable discrepancy between `convertToAssets` and `previewRedeem` SHOULD
    /// be considered slippage in share price or some other type of condition,
    /// meaning the depositor will lose assets by depositing.
    function previewRedeem(
        uint256 shares
    ) public view override returns (uint256 assets) {
        assets = _convertToAssetsWithdrawable(shares);
    }

    function _convertToAssetsWithdrawable(
        uint256 shares
    ) private view returns (uint256) {
        if (!_useVirtualShares()) {
            uint256 supply = totalSupply();
            return
                supply == uint256(0)
                    ? _initialConvertToAssets(shares)
                    : FixedPointMathLib.fullMulDiv(
                        shares,
                        totalAssetsWithdrawable(),
                        supply
                    );
        }
        uint256 o = _decimalsOffset();
        if (o == uint256(0)) {
            return
                FixedPointMathLib.fullMulDiv(
                    shares,
                    totalAssetsWithdrawable() + 1,
                    _inc_(totalSupply())
                );
        }
        return
            FixedPointMathLib.fullMulDiv(
                shares,
                totalAssetsWithdrawable() + 1,
                totalSupply() + 10 ** o
            );
    }

    function _convertToSharesWithdrawable(
        uint256 assets
    ) private view returns (uint256) {
        if (!_useVirtualShares()) {
            uint256 supply = totalSupply();
            return
                _eitherIsZero_(assets, supply)
                    ? _initialConvertToShares(assets)
                    : FixedPointMathLib.fullMulDiv(
                        assets,
                        supply,
                        totalAssetsWithdrawable()
                    );
        }
        uint256 o = _decimalsOffset();
        if (o == uint256(0)) {
            return
                FixedPointMathLib.fullMulDiv(
                    assets,
                    totalSupply() + 1,
                    _inc_(totalAssetsWithdrawable())
                );
        }
        return
            FixedPointMathLib.fullMulDiv(
                assets,
                totalSupply() + 10 ** o,
                _inc_(totalAssetsWithdrawable())
            );
    }

    function totalAssets() public view override returns (uint256 assets) {
        return _totalAssets;
    }

    // TODO: loop through the vaults to move the money
    function invest() external onlyRoles(INVESTOR_ROLE) {
        for (uint256 i = 0; i < WITHDRAWAL_QUEUE_SIZE; i++) {}
    }

    struct Report {
        uint16 chainId;
        address vault;
        uint256 totalAssets;
        uint256 totalAssetsWithdrawable;
    }

    // TODO: receive oracle call here
    function report(Report[] calldata reports) external onlyRoles(ORACLE_ROLE) {
        for (uint256 i = 0; i < reports.length; i++) {
            Report memory _report = reports[i];
            VaultData memory data = vaults[_report.vault];
            int256 totalAssetsDelta = int256(_report.totalAssets) -
                int256(data.totalAssets);
            int256 totalAssetsWithdrawableDelta = int256(
                _report.totalAssetsWithdrawable
            ) - int256(data.totalAssetsWithdrawable);

            if (totalAssetsDelta > 0) {
                _totalAssets += uint256(totalAssetsDelta);
            } else {
                _totalAssets -= uint256(-totalAssetsDelta);
            }

            if (totalAssetsWithdrawableDelta > 0) {
                _totalAssetsWithdrawable += uint256(
                    totalAssetsWithdrawableDelta
                );
            } else {
                _totalAssetsWithdrawable -= uint256(
                    -totalAssetsWithdrawableDelta
                );
            }
            vaults[_report.vault].totalAssets = _report.totalAssets;
            vaults[_report.vault].totalAssets = _report.totalAssets;
        }
    }

    // TODO: add vault to withdrawal queue
    function addVault(
        uint16 chain,
        uint256 superformId,
        uint256 debtRatio,
        address vault
    ) external {
        if (vaults[vault].vaultAddress == address(0)) revert();
        if (_totalDebt / (_totalDebt + _totalIdle) + debtRatio > MAX_BPS) {
            revert();
        }
        if (!factory.isSuperform(superformId)) revert();
        vaults[vault].chain = chain;
        vaults[vault].superformId = superformId;
        vaults[vault].debtRatio = debtRatio;
        vaults[vault].vaultAddress = vault;

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
    function setOracle(uint16 chain, address oracle) external {}

    function totalAssetsWithdrawable() public view returns (uint256) {
        return _totalAssetsWithdrawable;
    }

    /// @dev Hook that is called after any deposit or mint.
    function _afterDeposit(
        uint256 assets,
        uint256 /*uint256 shares*/
    ) internal override {
        _totalIdle += assets;
        _totalAssets += assets;
        _totalAssetsWithdrawable += assets;
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
    function _eitherIsZero_(
        uint256 a,
        uint256 b
    ) private pure returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := or(iszero(a), iszero(b))
        }
    }
}
