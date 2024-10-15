// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test, console2 } from "forge-std/Test.sol";
import { MaxApyCrossChainVault, ERC7540, ERC4626 } from "src/MaxApyCrossChainVault.sol";
import { MockERC4626Oracle } from "../helpers/mock/MockERC4626Oracle.sol";
import { BaseTest } from "../base/BaseTest.t.sol";
import { _1_USDCE } from "../helpers/Tokens.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IERC4626Oracle } from "src/interfaces/Lib.sol";
import {
    VaultReport,
    SingleVaultSFData,
    LiqRequest,
    SingleXChainSingleVaultStateReq,
    SingleXChainSingleVaultWithdraw,
    SingleXChainMultiVaultWithdraw,
    MultiXChainSingleVaultWithdraw,
    MultiXChainMultiVaultWithdraw
} from "src/types/Lib.sol";
import { SuperformActions } from "../helpers/SuperformActions.sol";
import "src/helpers/AddressBook.sol";
import { MaxApyCrossChainVaultEvents } from "../helpers/MaxApyCrossChainVaultEvents.sol";

contract MaxApyCrossChainVaultTest is BaseTest, SuperformActions, MaxApyCrossChainVaultEvents {
    using SafeTransferLib for address;

    MaxApyCrossChainVault public vault;
    ERC4626 public yUsdce;
    uint64 public constant POLYGON_CHAIN_ID = 137;
    uint24 public sharesLockTime = 30 days;
    uint256 public yUsdceSharePrice;
    MockERC4626Oracle public oracle;
    uint16 managementFee = 2000;
    uint16 oracleFee = 2000;
    uint24 processRedeemSettlement = 1 days;
    address treasury = makeAddr("treasury");

    function setUp() public override {
        super._setUp("POLYGON", 62_495_246);
        super.setUp();
        yUsdce = ERC4626(YEARN_USDCE_VAULT_POLYGON);
        vault = new MaxApyCrossChainVault({
            _asset_: USDCE_POLYGON,
            _name_: "maxCrossUSDCE",
            _symbol_: "maxCrossUSDCE",
            _managementFee: managementFee,
            _oracleFee: oracleFee,
            _sharesLockTime: sharesLockTime,
            _processRedeemSettlement: processRedeemSettlement,
            _superPositions_: superPositions,
            _vaultRouter_: vaultRouter,
            _factory_: factory,
            _treasury: treasury,
            _signerRelayer: address(1)
        });

        oracle = new MockERC4626Oracle();
        yUsdceSharePrice = yUsdce.convertToAssets(10 ** yUsdce.decimals());
        vault.grantRoles(users.alice, vault.MANAGER_ROLE());
        vault.grantRoles(users.alice, vault.ORACLE_ROLE());
        vault.grantRoles(users.alice, vault.RELAYER_ROLE());
        vault.grantRoles(users.alice, vault.EMERGENCY_ADMIN_ROLE());
        USDCE_POLYGON.safeApprove(address(vault), type(uint256).max);
    }

    function test_MaxApyCrossChainVault_initialization() public view {
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.asset(), USDCE_POLYGON);
        assertEq(vault.decimals(), 6);
        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.managementFee(), managementFee);
        assertEq(vault.oracleFee(), oracleFee);
        assertEq(vault.lastReport(), block.timestamp);
        assertEq(vault.treasury(), treasury);
    }

    function test_MaxApyCrossChainVault_depositAtomic() public {
        uint256 amount = 1000 * _1_USDCE;
        vm.expectEmit(true, true, true, true);
        emit DepositRequest(users.alice, users.alice, 0, users.alice, amount);
        vm.expectEmit(true, true, true, true);
        emit Deposit(users.alice, users.alice, amount, amount);
        uint256 shares = _depositAtomic(amount, users.alice, users.alice);
        assertEq(shares, amount);
        assertEq(vault.totalAssets(), amount);
        assertEq(vault.balanceOf(users.alice), amount);
    }

    function test_MaxApyCrossChainVault_mintAtomic() public {
        uint256 amount = 1000 * _1_USDCE;
        vm.expectEmit(true, true, true, true);
        emit DepositRequest(users.alice, users.alice, 0, users.alice, amount);
        vm.expectEmit(true, true, true, true);
        emit Deposit(users.alice, users.alice, amount, amount);
        uint256 assets = _mintAtomic(amount, users.alice, users.alice);
        assertEq(assets, amount);
        assertEq(vault.totalAssets(), amount);
        assertEq(vault.balanceOf(users.alice), amount);
    }

    function test_MaxApyCrossChainVault_investSingleDirectSingleVault() public {
        vault.addVault({
            chainId: 137,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            oracle: IERC4626Oracle(address(0))
        });
        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);
        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);

        vm.expectRevert(MaxApyCrossChainVault.InsufficientAssets.selector);
        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview + 1);

        vm.expectEmit(true, true, true, true);
        emit Invest(400 * _1_USDCE);
        uint256 shares = vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);
        assertEq(shares, depositPreview);
        assertEq(vault.totalAssets(), 1000 * _1_USDCE - 1);
        assertEq(vault.totalIdle(), 600 * _1_USDCE);
        assertEq(vault.totalDebt(), 400 * _1_USDCE);
        assertEq(yUsdce.balanceOf(address(vault)), depositPreview);
    }

    function test_MaxApyCrossChainVault_investSingleDirectMultiVault() public {
        vault.addVault({
            chainId: 137,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            oracle: IERC4626Oracle(address(0))
        });
        ERC4626 yUsdceLender = ERC4626(YEARN_USDCE_LENDER_VAULT_POLYGON);
        vault.addVault({
            chainId: 137,
            superformId: 2,
            vault: address(yUsdceLender),
            vaultDecimals: yUsdceLender.decimals(),
            oracle: IERC4626Oracle(address(0))
        });

        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);

        uint256 amountPerVault = 500 * _1_USDCE;

        address[] memory vaultAddresses = new address[](2);
        vaultAddresses[0] = address(yUsdce);
        vaultAddresses[1] = address(yUsdceLender);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountPerVault;
        amounts[1] = amountPerVault;

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = yUsdce.previewDeposit(amountPerVault);
        minAmountsOut[1] = yUsdceLender.previewDeposit(amountPerVault);

        minAmountsOut[1] += 1;

        vm.expectRevert(MaxApyCrossChainVault.InsufficientAssets.selector);
        vault.investSingleDirectMultiVault(vaultAddresses, amounts, minAmountsOut);

        minAmountsOut[1] -= 1;

        vm.expectEmit(true, true, true, true);
        emit Invest(500 * _1_USDCE);
        vault.investSingleDirectMultiVault(vaultAddresses, amounts, minAmountsOut);
        assertApproxEq(vault.totalAssets(), 1000 * _1_USDCE, 5);
        assertEq(vault.totalIdle(), 0 * _1_USDCE);
        assertEq(vault.totalDebt(), 1000 * _1_USDCE);
        assertEq(yUsdce.balanceOf(address(vault)), minAmountsOut[0]);
        assertEq(yUsdceLender.balanceOf(address(vault)), minAmountsOut[1]);
    }

    function test_MaxApyCrossChainVault_investSingleXChainSingleVault() public {
        address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint64 optimismChainId = 10;

        oracle.setValues(vaultAddress, _getSharePrice(optimismChainId, vaultAddress), block.timestamp);
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId,
            vault: vaultAddress,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress),
            oracle: IERC4626Oracle(address(oracle))
        });

        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);

        uint256 investAmount = 600 * _1_USDCE;
        (
            uint8[] memory ambIds,
            uint256 outputAmount,
            uint256 maxSlippage,
            LiqRequest memory liqRequest,
            bool hasDstSwap
        ) = _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);

        vm.expectEmit(true, true, true, true);
        emit Invest(investAmount);
        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            superformId, ambIds, investAmount, outputAmount, maxSlippage, liqRequest, hasDstSwap
        );
        assertEq(USDCE_POLYGON.balanceOf(address(vault)), 400 * _1_USDCE);
        assertEq(vault.totalAssets(), 1000 * _1_USDCE);
        assertEq(vault.totalXChainAssets(), 0);
        assertEq(vault.totalLocalAssets(), 400 * _1_USDCE);
        assertEq(vault.totalWithdrawableAssets(), 400 * _1_USDCE);
        _mintSuperpositions(address(vault), superformId, shares);
        assertEq(vault.totalAssets(), 999_999_482);
        assertEq(vault.totalWithdrawableAssets(), 999_999_482);
        assertEq(vault.totalXChainAssets(), 599_999_482);
        assertEq(vault.totalLocalAssets(), 400 * _1_USDCE);
        assertEq(vault.totalIdle(), 400 * _1_USDCE);
        assertEq(superPositions.balanceOf(address(vault), superformId), shares);
    }

    function test_revert_MaxApyCrossChainVault_redeem_requestNotProcessed() public {
        uint256 sharesBalance = _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);

        skip(sharesLockTime);
        vm.startPrank(users.alice);
        vault.requestRedeem(vault.balanceOf(users.alice), users.alice, users.alice);
        vm.expectRevert(MaxApyCrossChainVault.RedeemNotProcessed.selector);
        vault.redeem(sharesBalance, users.alice, users.alice);
    }

    function test_MaxApyCrossChainVault_processRedeemRequest_from_idle() public {
        uint256 sharesBalance = _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);
        skip(sharesLockTime);
        vault.requestRedeem(vault.balanceOf(users.alice), users.alice, users.alice);
        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;
        vm.expectEmit(true, true, true, true);
        emit ProcessRedeemRequest(users.alice, sharesBalance);
        vault.processRedeemRequest(users.alice, sXsV, sXmV, mXsV, mXmV);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.claimableRedeemRequest(users.alice), sharesBalance);
        assertEq(vault.pendingRedeemRequest(users.alice), 0);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(users.alice, users.alice, users.alice, 1000 * _1_USDCE, sharesBalance);
        uint256 assets = vault.redeem(sharesBalance, users.alice, users.alice);
        assertEq(assets, 1000 * _1_USDCE);
    }

    function test_MaxApyCrossChainVault_processRedeemRequest_from_local_queue() public {
        vault.addVault({
            chainId: 137,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            oracle: IERC4626Oracle(address(0))
        });
        uint256 sharesBalance = _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);
        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);
        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);
        uint256 totalAssetsBeforeLock = vault.totalAssets();
        uint256 sharePriceBeforeLock = vault.sharePrice();
        skip(sharesLockTime);
        uint256 totalAssetsAfterLock = vault.totalAssets();
        uint256 sharePriceAfterLock = vault.sharePrice();
        assertGt(totalAssetsAfterLock, totalAssetsBeforeLock);
        assertGt(sharePriceAfterLock, sharePriceBeforeLock);
        vault.requestRedeem(vault.balanceOf(users.alice), users.alice, users.alice);
        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;
        vm.expectEmit(true, true, true, true);
        emit ProcessRedeemRequest(users.alice, sharesBalance);
        vault.processRedeemRequest(users.alice, sXsV, sXmV, mXsV, mXmV);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 2);
        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.claimableRedeemRequest(users.alice), sharesBalance);
        assertEq(vault.pendingRedeemRequest(users.alice), 0);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(users.alice, users.alice, users.alice, totalAssetsAfterLock - 2, sharesBalance);
        uint256 assets = vault.redeem(sharesBalance, users.alice, users.alice);
        assertEq(assets, totalAssetsAfterLock - 2);
    }

    // TODO
    function test_MaxApyCrossChainVault_processRedeemRequest_from_local_and_xchain_queue() public {
        vault.addVault({
            chainId: 137,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            oracle: IERC4626Oracle(address(0))
        });
        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);
        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);

        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);

        address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint64 optimismChainId = 10;

        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId,
            vault: vaultAddress,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress),
            oracle: IERC4626Oracle(address(oracle))
        });

        oracle.setValues(vaultAddress, _getSharePrice(optimismChainId, vaultAddress), block.timestamp);

        uint256 investAmount = 600 * _1_USDCE;
        (
            uint8[] memory ambIds,
            uint256 outputAmount,
            uint256 maxSlippage,
            LiqRequest memory liqRequest,
            bool hasDstSwap
        ) = _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);

        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            superformId, ambIds, investAmount, outputAmount, maxSlippage, liqRequest, hasDstSwap
        );

        _mintSuperpositions(address(vault), superformId, shares);

        vm.startPrank(users.alice);

        vault.setSharesLockTime(0);

        vault.requestRedeem(vault.balanceOf(users.alice), users.alice, users.alice);

        {
            oracle.setValues(vaultAddress, _getSharePrice(optimismChainId, vaultAddress), block.timestamp);
        }
        {
            SingleXChainSingleVaultWithdraw memory sXsV;
            SingleXChainMultiVaultWithdraw memory sXmV;
            MultiXChainSingleVaultWithdraw memory mXsV;
            MultiXChainMultiVaultWithdraw memory mXmV;
            (sXsV.ambIds, sXsV.outputAmount, sXsV.maxSlippage, sXsV.liqRequest, sXsV.hasDstSwap) =
                _buildWithdrawSingleXChainSingleVaultParams(superformId, investAmount);
            vm.expectEmit(true, true, true, true);
            emit ProcessRedeemRequest(users.alice, vault.balanceOf(users.alice));
            vault.processRedeemRequest{ value: _getWithdrawSingleXChainSingleVaultValue(superformId, investAmount) }(
                users.alice, sXsV, sXmV, mXsV, mXmV
            );
        }
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function test_revert_MaxApyCrossChainVault_redeem_requestNotSettled() public {
        uint256 sharesBalance;
        uint256 investAmount;
        uint256 superformId = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        {
            address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
            uint64 optimismChainId = 10;
            oracle.setValues(vaultAddress, _getSharePrice(optimismChainId, vaultAddress), block.timestamp);

            vault.addVault({
                chainId: optimismChainId,
                superformId: superformId,
                vault: vaultAddress,
                vaultDecimals: _getDecimals(optimismChainId, vaultAddress),
                oracle: IERC4626Oracle(address(oracle))
            });

            sharesBalance = _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);

            investAmount = 600 * _1_USDCE;
            (
                uint8[] memory ambIds,
                uint256 outputAmount,
                uint256 maxSlippage,
                LiqRequest memory liqRequest,
                bool hasDstSwap
            ) = _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

            uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);

            vault.investSingleXChainSingleVault{
                value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount)
            }(superformId, ambIds, investAmount, outputAmount, maxSlippage, liqRequest, hasDstSwap);
            _mintSuperpositions(address(vault), superformId, shares);
        }
        vm.startPrank(users.alice);
        vault.requestRedeem(vault.balanceOf(users.alice), users.alice, users.alice);

        {
            SingleXChainSingleVaultWithdraw memory sXsV;
            SingleXChainMultiVaultWithdraw memory sXmV;
            MultiXChainSingleVaultWithdraw memory mXsV;
            MultiXChainMultiVaultWithdraw memory mXmV;
            (sXsV.ambIds, sXsV.outputAmount, sXsV.maxSlippage, sXsV.liqRequest, sXsV.hasDstSwap) =
                _buildWithdrawSingleXChainSingleVaultParams(superformId, investAmount);
            vault.processRedeemRequest{ value: _getWithdrawSingleXChainSingleVaultValue(superformId, investAmount) }(
                users.alice, sXsV, sXmV, mXsV, mXmV
            );
        }

        vm.expectRevert(MaxApyCrossChainVault.RequestNotSettled.selector);
        vault.redeem(sharesBalance, users.alice, users.alice);
    }

    function test_revert_MaxApyCrossChainVault_report_VaultNotListed() public {
        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);
        skip(vault.SECS_PER_YEAR());
        VaultReport[] memory mockReport = new VaultReport[](1);
        mockReport[0].chainId = uint64(1);
        mockReport[0].sharePrice = uint192(2 * _1_USDCE);
        mockReport[0].vaultAddress = makeAddr("random address");

        vm.expectRevert(MaxApyCrossChainVault.VaultNotListed.selector);
        vault.report(mockReport, users.bob);
    }

    function test_MaxApyCrossChainVault_report() public {
        address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint64 optimismChainId = 10;

        oracle.setValues(vaultAddress, _getSharePrice(optimismChainId, vaultAddress), block.timestamp);
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId,
            vault: vaultAddress,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress),
            oracle: IERC4626Oracle(address(oracle))
        });

        _depositAtomic(1000 * _1_USDCE, users.alice, users.alice);

        uint256 investAmount = 600 * _1_USDCE;
        (
            uint8[] memory ambIds,
            uint256 outputAmount,
            uint256 maxSlippage,
            LiqRequest memory liqRequest,
            bool hasDstSwap
        ) = _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        uint256 newSharesPrice = 2 * _1_USDCE;
        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);

        vm.expectEmit(true, true, true, true);
        emit Invest(investAmount);
        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            superformId, ambIds, investAmount, outputAmount, maxSlippage, liqRequest, hasDstSwap
        );

        _mintSuperpositions(address(vault), superformId, shares);
        vm.startPrank(users.alice);
        VaultReport[] memory mockReport = new VaultReport[](1);
        mockReport[0].chainId = optimismChainId;
        mockReport[0].sharePrice = uint192(newSharesPrice);
        mockReport[0].vaultAddress = vaultAddress;

        skip(vault.SECS_PER_YEAR());
        oracle.setValues(vaultAddress, newSharesPrice, block.timestamp);

        vm.expectEmit(true, true, true, true);
        emit Report(optimismChainId, vaultAddress, 566_695_022);
        vault.report(mockReport, users.bob);
        assertApproxEq(vault.balanceOf(treasury), 200 * _1_USDCE, 2);
        assertApproxEq(vault.balanceOf(users.bob), 200 * _1_USDCE, 2);
    }

    function test_MaxApyCrossChainVault_addVault() public {
        address newVault = address(0x123);
        uint256 newSuperformId = 999;
        uint64 newChainId = 42;
        uint8 newDecimals = 18;
        oracle.setValues(newVault, 1 * _1_USDCE, block.timestamp);
        vm.expectEmit(true, true, true, true);
        emit AddVault(newChainId, newVault);
        vault.addVault(newChainId, newSuperformId, newVault, newDecimals, IERC4626Oracle(address(oracle)));

        assertTrue(vault.isVaultListed(newVault));
    }

    function test_MaxApyCrossChainVault_addVault_ZeroSharePrice() public {
        address newVault = address(0x123);
        uint256 newSuperformId = 999;
        uint64 newChainId = 42;
        uint8 newDecimals = 18;

        vm.expectRevert();
        vault.addVault(newChainId, newSuperformId, newVault, newDecimals, IERC4626Oracle(address(oracle)));
    }

    function test_revert_MaxApyCrossChainVault_addVault_alreadyListed() public {
        uint8 decimals = yUsdce.decimals();
        vault.addVault({
            chainId: 137,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: decimals,
            oracle: IERC4626Oracle(address(0))
        });
        vm.expectRevert(MaxApyCrossChainVault.VaultAlreadyListed.selector);
        vault.addVault({
            chainId: 137,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: decimals,
            oracle: IERC4626Oracle(address(0))
        });
    }

    function test_MaxApyCrossChainVault_setOracle() public {
        address newOracle = address(0x789);
        uint64 chainId = 42;

        vm.expectEmit(true, true, true, true);
        emit SetOracle(chainId, newOracle);
        vault.setOracle(chainId, newOracle);
    }

    function test_MaxApyCrossChainVault_setSharesLockTime() public {
        uint24 newLockTime = 60 days;

        vm.expectEmit(true, true, true, true);
        emit SetSharesLockTime(newLockTime);
        vault.setSharesLockTime(newLockTime);

        assertEq(vault.sharesLockTime(), newLockTime);
    }

    function test_MaxApyCrossChainVault_setManagementFee() public {
        uint16 newFee = 3000;

        vm.expectEmit(true, true, true, true);
        emit SetManagementFee(newFee);
        vault.setManagementFee(newFee);

        assertEq(vault.managementFee(), newFee);
    }

    function test_MaxApyCrossChainVault_setOracleFee() public {
        uint16 newFee = 2500;

        vm.expectEmit(true, true, true, true);
        emit SetOracleFee(newFee);
        vault.setOracleFee(newFee);

        assertEq(vault.oracleFee(), newFee);
    }

    function test_revert_MaxApyCrossChainVault_emergencyShutdown() public {
        vault.setEmergencyShutdown(true);

        vm.expectRevert(MaxApyCrossChainVault.VaultShutdown.selector);
        vault.requestDeposit(100 * _1_USDCE, users.alice, users.alice);
    }

    function test_MaxApyCrossChainVault_onERC1155Received() public {
        uint256 superformId = 1;
        uint256 bridgedAssets = 1000 * _1_USDCE;

        vm.expectEmit(true, true, true, true);
        emit SettleXChainInvest(superformId, 0);
        vault.onERC1155Received(address(0), address(0), superformId, bridgedAssets, "");
    }

    function test_MaxApyCrossChainVault_onERC1155BatchReceived() public {
        uint256[] memory superformIds = new uint256[](2);
        superformIds[0] = 1;
        superformIds[1] = 2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 500 * _1_USDCE;
        amounts[1] = 500 * _1_USDCE;

        vm.expectEmit(true, true, true, true);
        emit SettleXChainInvest(superformIds[0], 0);
        vm.expectEmit(true, true, true, true);
        emit SettleXChainInvest(superformIds[1], 0);
        vault.onERC1155BatchReceived(address(0), address(0), superformIds, amounts, "");
    }

    function test_revert_MaxApyCrossChainVault_invalidController() public {
        uint256 amount = 100 * _1_USDCE;
        vault.requestDeposit(amount, users.alice, users.alice);

        vm.startPrank(users.bob);
        vm.expectRevert(ERC7540.InvalidController.selector);
        vault.deposit(amount, users.bob, users.alice);
    }

    function test_MaxApyCrossChainVault_setOperator() public {
        uint256 amount = 100 * _1_USDCE;
        vm.startPrank(users.alice);
        vm.expectEmit(true, true, true, true);
        emit OperatorSet(users.alice, users.bob, true);
        vault.setOperator(users.bob, true);
        vault.requestDeposit(amount, users.alice, users.alice);
        vm.stopPrank();

        assertTrue(vault.isOperator(users.alice, users.bob));

        // Now bob should be able to deposit on behalf of alice
        vm.startPrank(users.bob);
        vault.deposit(amount, users.alice, users.alice);
    }

    function test_revert_MaxApyCrossChainVault_setOperator_invalidOperator() public {
        vm.expectRevert(ERC7540.InvalidOperator.selector);
        vault.setOperator(users.alice, true);
    }

    function _depositAtomic(uint256 assets, address receiver, address sender) private returns (uint256 shares) {
        bytes[] memory callDatas = new bytes[](2);
        callDatas[0] =
            abi.encodeWithSelector(MaxApyCrossChainVault.requestDeposit.selector, assets, receiver, users.alice);
        callDatas[1] = abi.encodeWithSignature("deposit(uint256,address)", assets, receiver);
        bytes[] memory returnData = vault.multicall(callDatas);
        return abi.decode(returnData[1], (uint256));
    }

    function _mintAtomic(uint256 shares, address receiver, address sender) private returns (uint256 assets) {
        bytes[] memory callDatas = new bytes[](2);
        uint256 assets = vault.convertToAssets(shares);
        callDatas[0] =
            abi.encodeWithSelector(MaxApyCrossChainVault.requestDeposit.selector, assets, receiver, users.alice);
        callDatas[1] = abi.encodeWithSignature("mint(uint256,address)", shares, receiver);
        bytes[] memory returnData = vault.multicall(callDatas);
        return abi.decode(returnData[1], (uint256));
    }
}
