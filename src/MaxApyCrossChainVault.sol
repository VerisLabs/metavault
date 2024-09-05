/// SPDX-License-Identifer: MIT
pragma solidity 0.8.21;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { ERC7540, ReentrancyGuard } from "./lib/Lib.sol";
import { ISuperPositions, IBaseRouter, ISuperformFactory } from "./interfaces/Lib.sol";
import { VaultData, VaultReport } from "./types/Lib.sol";

/// @title MaxApyCrossChainVault
/// @author Unlockd
/// notice description
contract MaxApyCrossChainVault is ERC7540, OwnableRoles, ReentrancyGuard {
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

    function deposit(uint256 assets, address to) public override returns (uint256 shares) {
        return deposit(assets, to , msg.sender);
    }

    function deposit(uint256 assets, address to, address controller) public override noEmergencyShutdown returns (uint256 shares) {
        return super.deposit(assets, to, controller);
    }

    function mint(uint256 shares, address to) public override returns (uint256 assets) {
        return mint(shares, to , msg.sender);
    }

    function mint(uint256 shares, address to, address controller) public override noEmergencyShutdown returns (uint256 assets) {
        return super.mint(shares, to , controller);
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
    function setOracle(uint16 chain, address oracle) external onlyRoles(ADMIN_ROLE) {
        oracles[chain] = oracle;
    }

    /// @dev Hook that is called after any deposit or mint.
    function _afterDeposit(uint256 assets, uint256 /*uint256 shares*/ ) internal override {
        _totalIdle += assets;
        _totalAssets += assets;
    }
}
