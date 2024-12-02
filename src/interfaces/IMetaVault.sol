/// SPDX-License-Identifer: MIT
pragma solidity ^0.8.19;

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
} from "types/Lib.sol";

interface IMetaVault {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function asset() external view returns (address);

    function totalAssets() external view returns (uint256 assets);

    function totalWithdrawableAssets() external view returns (uint256 assets);

    function totalLocalAssets() external view returns (uint256 assets);

    function totalXChainAssets() external view returns (uint256 assets);

    function sharePrice() external view returns (uint256);

    function totalIdle() external view returns (uint256 assets);

    function totalDebt() external view returns (uint256 assets);

    function isVaultListed(address vaultAddress) external view returns (bool);

    function isVaultListed(uint256 superformId) external view returns (bool);

    function getVault(uint256 superformId) external view returns (VaultData memory vault);

    function requestDeposit(uint256 assets, address controller, address owner) external returns (uint256 requestId);

    function deposit(uint256 assets, address to) external returns (uint256 shares);

    function deposit(uint256 assets, address to, address controller) external returns (uint256 shares);

    function mint(uint256 shares, address to) external returns (uint256 assets);

    function mint(uint256 shares, address to, address controller) external returns (uint256 assets);

    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId);

    function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assets);

    function withdraw(uint256 assets, address receiver, address controller) external returns (uint256 shares);

    function processRedeemRequest(
        address controller,
        SingleXChainSingleVaultWithdraw calldata sXsV,
        SingleXChainMultiVaultWithdraw calldata sXmV,
        MultiXChainSingleVaultWithdraw calldata mXsV,
        MultiXChainMultiVaultWithdraw calldata mXmV
    )
        external
        payable;

    function processRedeemRequestWithSignature(ProcessRedeemRequestWithSignatureParams calldata params)
        external
        payable;

    function investSingleDirectSingleVault(
        address vaultAddress,
        uint256 assets,
        uint256 minSharesOut
    )
        external
        returns (uint256 shares);

    function investSingleDirectMultiVault(
        address[] calldata vaultAddresses,
        uint256[] calldata assets,
        uint256[] calldata minSharesOuts
    )
        external
        returns (uint256[] memory shares);

    function investSingleXChainSingleVault(SingleXChainSingleVaultStateReq calldata req) external payable;

    function investSingleXChainMultiVault(SingleXChainMultiVaultStateReq calldata req) external payable;

    function investMultiXChainSingleVault(MultiDstSingleVaultStateReq calldata req) external payable;

    function investMultiXChainMultiVault(MultiDstMultiVaultStateReq calldata req) external payable;

    function divestSingleDirectSingleVault(
        address vaultAddress,
        uint256 shares,
        uint256 minAssetsOut
    )
        external
        returns (uint256 assets);

    function divestSingleDirectMultiVault(
        address[] calldata vaultAddresses,
        uint256[] calldata shares,
        uint256[] calldata minAssetsOuts
    )
        external
        payable
        returns (uint256[] memory assets);

    function divestSingleXChainSingleVault(SingleXChainSingleVaultStateReq calldata req) external payable;

    function divestSingleXChainMultiVault(SingleXChainMultiVaultStateReq calldata req) external payable;

    function divestMultiXChainSingleVault(MultiDstSingleVaultStateReq calldata req) external payable;

    function divestMultiXChainMultiVault(MultiDstMultiVaultStateReq calldata req) external payable;

    function setEmergencyShutdown(bool _emergencyShutdown) external;

    function setOracle(uint64 chainId, address oracle) external;

    function setSharesLockTime(uint24 time) external;

    function setManagementFee(uint16 _managementFee) external;

    function setPerformanceFee(uint16 _performanceFee) external;

    function setOracleFee(uint16 _oracleFee) external;

    function setRecoveryAddress(address _recoveryAddress) external;

    function fulfillSettledRequest(address controller, uint256 requestedAssets, uint256 settledAssets) external;

    function settleXChainInvest(uint256 superformId, uint256 bridgedAssets) external;

    function settleXChainDivest(uint256 superformId, uint256 withdrawn) external;
}
