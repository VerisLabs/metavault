/// SPDX-License-Identifer: MIT
pragma solidity 0.8.21;

import { ERC4626, OwnableRoles, FixedPointMathLib, VaultData } from "./lib/Index.sol";

/// @title SuperVault
/// @author Unlockd
/// @description
contract SuperVault is ERC4626, OwnableRoles {
    // CONSTANTS
    uint256 public constant WITHDRAWAL_QUEUE_SIZE = 30;
    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant EMERGENCY_ADMIN_ROLE = _ROLE_1;
    uint256 public constant ORACLE_ROLE = _ROLE_2;
    uint256 public constant INVESTOR_ROLE = _ROLE_3;

    // STORAGE
    mapping(uint256 superformId => VaultData) public vaults;
    mapping(uint16 chain => address) public oracles;
    uint256[WITHDRAWAL_QUEUE_SIZE] public withdrawalQue;
    uint256 private _totalAssets;
    uint256 private _totalAssetsWithdrawable;
    address private immutable _asset;
    string private _name;
    string private _symbol;
    uint256 private _totalIdle;
    uint256 private _totalDebt;
    uint256 managementFee;
    address treasury;

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

    function _convertToAssetsWithdrawable(uint256 shares) private view returns (uint256) {
        if (!_useVirtualShares()) {
            uint256 supply = totalSupply();
            return supply == uint256(0)
                ? _initialConvertToAssets(shares)
                : FixedPointMathLib.fullMulDiv(shares, totalAssetsWithdrawable(), supply);
        }
        uint256 o = _decimalsOffset();
        if (o == uint256(0)) {
            return FixedPointMathLib.fullMulDiv(shares, totalAssetsWithdrawable() + 1, _inc_(totalSupply()));
        }
        return FixedPointMathLib.fullMulDiv(shares, totalAssetsWithdrawable() + 1, totalSupply() + 10 ** o);
    }

    function _convertToSharesWithdrawable(uint256 assets) private view returns (uint256) {
        if (!_useVirtualShares()) {
            uint256 supply = totalSupply();
            return _eitherIsZero_(assets, supply)
                ? _initialConvertToShares(assets)
                : FixedPointMathLib.fullMulDiv(assets, supply, totalAssetsWithdrawable());
        }
        uint256 o = _decimalsOffset();
        if (o == uint256(0)) {
            return FixedPointMathLib.fullMulDiv(assets, totalSupply() + 1, _inc_(totalAssetsWithdrawable()));
        }
        return FixedPointMathLib.fullMulDiv(assets, totalSupply() + 10 ** o, _inc_(totalAssetsWithdrawable()));
    }

    function totalAssets() public view override returns (uint256 assets) {
        return _totalAssets;
    }

    // TODO: loop through the vaults to move the money
    function invest() external { }

    // TODO: receive oracle call here
    function report() external { }

    // TODO: add vault to withdrawal queue
    function addVault() external { }

    // TODO: update vault allocation
    function updateVaultData() external { }

    // TODO: set the oracle for a chain
    function setOracle(uint16 chain, address oracle) external { }

    function totalAssetsWithdrawable() public view returns (uint256) {
        return _totalAssetsWithdrawable;
    }

    /// @dev Hook that is called after any deposit or mint.
    function _afterDeposit(uint256 assets, uint256 /*uint256 shares*/ ) internal override {
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
    function _eitherIsZero_(uint256 a, uint256 b) private pure returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := or(iszero(a), iszero(b))
        }
    }
}
