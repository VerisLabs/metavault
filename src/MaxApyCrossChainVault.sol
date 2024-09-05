/// SPDX-License-Identifer: MIT
pragma solidity 0.8.21;

import {
    ERC7540,
    SafeTransferLib,
    OwnableRoles,
    ReentrancyGuard,
    FixedPointMathLib,
    VaultData,
    VaultReport,
    ISuperPositions,
    IBaseRouter,
    ISuperformFactory
} from "./lib/Index.sol";

/// @title MaxApyCrossChainVault
/// @author Unlockd
/// notice description
contract MaxApyCrossChainVault is ERC7540, OwnableRoles, ReentrancyGuard {
    // EVENTS
    /// @dev `keccak256(bytes("Withdraw(address,address,address,uint256,uint256)"))`.
    uint256 private constant _WITHDRAW_EVENT_SIGNATURE =
        0xfbde797d201c681b91056529119e0b02407c7bb96a4a2c75c01fc9667232c8db;

    //  CONSTANTS
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
    bool emergencyShutdown;

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

    function deposit(uint256 assets, address to) public override noEmergencyShutdown returns (uint256 shares) {
        return super.deposit(assets, to);
    }

    function mint(uint256 shares, address to) public override noEmergencyShutdown returns (uint256 assets) {
        return super.mint(shares, to);
    }

    /// @dev Burns `shares` from `owner` and sends exactly `assets` of underlying tokens to `to`.
    ///
    /// - MUST emit the {Withdraw} event.
    /// - MAY support an additional flow in which the underlying tokens are owned by the Vault
    ///   contract before the withdraw execution, and are accounted for during withdraw.
    /// - MUST revert if all of `assets` cannot be withdrawn, such as due to withdrawal limit,
    ///   slippage, insufficient balance, etc.
    ///
    /// Note: Some implementations will require pre-requesting to the Vault before a withdrawal
    /// may be performed. Those methods should be performed separately.
    function withdraw(
        uint256 assets,
        address to,
        address owner
    )
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        if (assets > maxWithdraw(owner)) revert WithdrawMoreThanMax();
        shares = previewWithdraw(assets);
        _withdraw(msg.sender, to, owner, assets, shares);
    }

    /// @dev Burns exactly `shares` from `owner` and sends `assets` of underlying tokens to `to`.
    ///
    /// - MUST emit the {Withdraw} event.
    /// - MAY support an additional flow in which the underlying tokens are owned by the Vault
    ///   contract before the redeem execution, and are accounted for during redeem.
    /// - MUST revert if all of shares cannot be redeemed, such as due to withdrawal limit,
    ///   slippage, insufficient balance, etc.
    ///
    /// Note: Some implementations will require pre-requesting to the Vault before a redeem
    /// may be performed. Those methods should be performed separately.
    function redeem(uint256 shares, address to, address owner) public override nonReentrant returns (uint256 assets) {
        // TODO: revert function
        if (shares > maxRedeem(owner)) revert RedeemMoreThanMax();
        return _redeem(msg.sender, to, owner, shares);
    }

    function _redeem(address by, address to, address owner, uint256 shares) private returns (uint256 assets) {
        if (shares == type(uint256).max) shares = maxRedeem(owner);
        if (shares > maxRedeem(owner)) {
            assembly ("memory-safe") {
                mstore(0x00, 0x4656425a) // `RedeemMoreThanMax()`.
                revert(0x1c, 0x04)
            }
        }
        // substract losses to the total assets
        assets = _redeem(msg.sender, to, owner, shares);
    }

    /// @dev returns the total assets held by the vault
    function totalAssets() public view override returns (uint256 assets) {
        return _totalAssets;
    }

    // TODO: loop through the vaults to move the money
    function invest() external onlyRoles(INVESTOR_ROLE) {
        for (uint256 i = 0; i < WITHDRAWAL_QUEUE_SIZE; i++) { }
    }

    // TODO: receive oracle call here
    function report(VaultReport[] calldata reports) external onlyRoles(ORACLE_ROLE) {
        for (uint256 i = 0; i < reports.length; i++) {
            VaultReport memory _report = reports[i];
            VaultData memory data = vaults[_report.vault];
            int256 totalAssetsDelta = int256(_report.totalAssets) - int256(data.totalAssets);
            int256 totalAssetsWithdrawableDelta =
                int256(_report.totalAssetsWithdrawable) - int256(data.totalAssetsWithdrawable);

            if (totalAssetsDelta > 0) {
                _totalAssets += uint256(totalAssetsDelta);
            } else {
                _totalAssets -= uint256(-totalAssetsDelta);
            }

            if (totalAssetsWithdrawableDelta > 0) { } else { }
            vaults[_report.vault].totalAssets = _report.totalAssets;
            vaults[_report.vault].totalAssets = _report.totalAssets;
        }
    }

    // TODO: add vault to withdrawal queue
    function addVault(uint16 chain, uint256 superformId, uint256 debtRatio, address vault) external {
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
    function setOracle(uint16 chain, address oracle) external { }

    /// @dev Hook that is called after any deposit or mint.
    function _afterDeposit(uint256 assets, uint256 /*uint256 shares*/ ) internal override {
        _totalIdle += assets;
        _totalAssets += assets;
    }
}
