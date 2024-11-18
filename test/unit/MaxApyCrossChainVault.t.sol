// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { BaseVaultTest } from "../base/BaseVaultTest.t.sol";

import { MaxApyCrossChainVaultEvents } from "../helpers/MaxApyCrossChainVaultEvents.sol";
import { SuperformActions } from "../helpers/SuperformActions.sol";
import { _1_USDCE } from "../helpers/Tokens.sol";

import { MockERC4626 } from "../helpers/mock/MockERC4626.sol";
import { MockERC4626Oracle } from "../helpers/mock/MockERC4626Oracle.sol";
import { MockSignerRelayer } from "../helpers/mock/MockSignerRelayer.sol";
import { Test, console2 } from "forge-std/Test.sol";

import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { ERC4626, ERC7540, MaxApyCrossChainVault } from "src/MaxApyCrossChainVault.sol";

import {
    EXACTLY_USDC_VAULT_ID_OPTIMISM,
    EXACTLY_USDC_VAULT_OPTIMISM,
    LAYERZERO_ULTRALIGHT_NODE_BASE,
    SUPERFORM_CORE_STATE_REGISTRY_BASE,
    SUPERFORM_LAYERZERO_ENDPOINT_BASE,
    SUPERFORM_LAYERZERO_IMPLEMENTATION_BASE,
    SUPERFORM_LAYERZERO_V2_IMPLEMENTATION_BASE,
    SUPERFORM_PAYMASTER_BASE,
    SUPERFORM_PAYMENT_HELPER_BASE,
    SUPERFORM_ROUTER_BASE,
    SUPERFORM_SUPEREGISTRY_BASE,
    SUPERFORM_SUPERPOSITIONS_BASE,
    USDCE_BASE
} from "src/helpers/AddressBook.sol";
import { IERC4626Oracle } from "src/interfaces/Lib.sol";
import {
    LiqRequest,
    MultiXChainMultiVaultWithdraw,
    MultiXChainSingleVaultWithdraw,
    ProcessRedeemRequestWithSignatureParams,
    SingleVaultSFData,
    SingleXChainMultiVaultWithdraw,
    SingleXChainSingleVaultStateReq,
    SingleXChainSingleVaultWithdraw,
    VaultReport
} from "src/types/Lib.sol";

contract MaxApyCrossChainVaultTest is BaseVaultTest, SuperformActions, MaxApyCrossChainVaultEvents {
    using SafeTransferLib for address;

    MockERC4626Oracle public oracle;
    MockSignerRelayer public relayer;
    uint64 baseChainId = 8453;

    function _setUpTestEnvironment() private {
        config = baseChainUsdceVaultConfig();
        relayer = new MockSignerRelayer(0xA111ce);
        config.signerRelayer = relayer.signerAddress();

        vault = new MaxApyCrossChainVault(config);
        oracle = new MockERC4626Oracle();
        vault.grantRoles(users.alice, vault.MANAGER_ROLE());
        vault.grantRoles(users.alice, vault.ORACLE_ROLE());
        vault.grantRoles(users.alice, vault.RELAYER_ROLE());
        vault.grantRoles(users.alice, vault.EMERGENCY_ADMIN_ROLE());
        USDCE_BASE.safeApprove(address(vault), type(uint256).max);

        console2.log("vault address : %s", address(vault));
    }

    function _setupContractLabels() private {
        vm.label(SUPERFORM_SUPEREGISTRY_BASE, "SuperRegistry");
        vm.label(SUPERFORM_SUPERPOSITIONS_BASE, "SuperPositions");
        vm.label(SUPERFORM_PAYMENT_HELPER_BASE, "PaymentHelper");
        vm.label(SUPERFORM_PAYMASTER_BASE, "PayMaster");
        //      vm.label(SUPERFORM_LAYERZERO_V2_IMPLEMENTATION_BASE, "LayerZeroV2Implementation");
        //       vm.label(SUPERFORM_LAYERZERO_IMPLEMENTATION_BASE, "LayerZeroImplementation");
        vm.label(SUPERFORM_LAYERZERO_ENDPOINT_BASE, "LayerZeroEndpoint");
        vm.label(SUPERFORM_CORE_STATE_REGISTRY_BASE, "CoreStateRegistry");
        //      vm.label(LAYERZERO_ULTRALIGHT_NODE_BASE, "UltraLightNode");
        vm.label(SUPERFORM_ROUTER_BASE, "SuperRouter");
        vm.label(address(vault), "MaxApyCrossChainVault");
        vm.label(USDCE_BASE, "USDC");
        vm.label(address(oracle), "SharePriceOracle");
        vm.label(address(relayer), "Relayer");
    }

    function setUp() public override {
        super._setUp("BASE", 22_567_511);
        super.setUp();

        _setUpTestEnvironment();
        _setupContractLabels();
    }

    function test_MaxApyCrossChainVault_initialization() public view {
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.asset(), USDCE_BASE);
        assertEq(vault.decimals(), 6);
        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.managementFee(), 0);
        assertEq(vault.performanceFee(), 2000);
        assertEq(vault.oracleFee(), 300);
        assertEq(vault.hurdleRate(), 600);
        assertEq(vault.lastReport(), block.timestamp);
        assertEq(vault.treasury(), config.treasury);
    }

    function test_MaxApyCrossChainVault_depositAtomic() public {
        uint256 amount = 1000 * _1_USDCE;
        vm.expectEmit(true, true, true, true);
        emit DepositRequest(users.alice, users.alice, 0, users.alice, amount);
        vm.expectEmit(true, true, true, true);
        emit Deposit(users.alice, users.alice, amount, amount);
        uint256 shares = _depositAtomic(amount, users.alice);
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
        uint256 assets = _mintAtomic(amount, users.alice);
        assertEq(assets, amount);
        assertEq(vault.totalAssets(), amount);
        assertEq(vault.balanceOf(users.alice), amount);
    }

    function test_MaxApyCrossChainVault_investSingleDirectSingleVault() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);

        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            deductedFees: 0,
            oracle: IERC4626Oracle(address(0))
        });
        _depositAtomic(1000 * _1_USDCE, users.alice);
        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);

        vm.expectRevert(MaxApyCrossChainVault.InsufficientAssets.selector);
        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview + 1);

        vm.expectEmit(true, true, true, true);
        emit Invest(400 * _1_USDCE);
        uint256 shares = vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);
        assertEq(shares, depositPreview);
        assertEq(vault.totalAssets(), 1000 * _1_USDCE);
        assertEq(vault.totalIdle(), 600 * _1_USDCE);
        assertEq(vault.totalDebt(), 400 * _1_USDCE);
        assertEq(yUsdce.balanceOf(address(vault)), depositPreview);
    }

    function test_MaxApyCrossChainVault_investSingleDirectMultiVault() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        MockERC4626 smUsdce = new MockERC4626(USDCE_BASE, "Sommelier USDCE", "smUSDCe", true, 0);

        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            deductedFees: 0,
            oracle: IERC4626Oracle(address(0))
        });
        vault.addVault({
            chainId: baseChainId,
            superformId: 2,
            vault: address(smUsdce),
            vaultDecimals: smUsdce.decimals(),
            deductedFees: 0,
            oracle: IERC4626Oracle(address(0))
        });

        _depositAtomic(1000 * _1_USDCE, users.alice);

        uint256 amountPerVault = 500 * _1_USDCE;

        address[] memory vaultAddresses = new address[](2);
        vaultAddresses[0] = address(yUsdce);
        vaultAddresses[1] = address(smUsdce);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountPerVault;
        amounts[1] = amountPerVault;

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = yUsdce.previewDeposit(amountPerVault);
        minAmountsOut[1] = smUsdce.previewDeposit(amountPerVault);

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
        assertEq(smUsdce.balanceOf(address(vault)), minAmountsOut[1]);
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
            deductedFees: 0,
            oracle: IERC4626Oracle(address(oracle))
        });

        _depositAtomic(1000 * _1_USDCE, users.alice);

        uint256 investAmount = 600 * _1_USDCE;
        (SingleXChainSingleVaultStateReq memory req) =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        req.superformData.amount = investAmount; // the API sets the amount slightly higher

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);

        vm.startPrank(users.alice);
        vm.expectEmit(true, true, true, true);
        emit Invest(investAmount);
        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            req
        );
        assertEq(USDCE_BASE.balanceOf(address(vault)), 400 * _1_USDCE);
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
        assertEq(config.superPositions.balanceOf(address(vault), superformId), shares);
    }

    function test_MaxApyCrossChainVault_refund_gas() public {
        address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint64 optimismChainId = 10;

        oracle.setValues(vaultAddress, _getSharePrice(optimismChainId, vaultAddress), block.timestamp);
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId,
            vault: vaultAddress,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress),
            deductedFees: 0,
            oracle: IERC4626Oracle(address(oracle))
        });

        _depositAtomic(1000 * _1_USDCE, users.alice);

        uint256 investAmount = 600 * _1_USDCE;
        (SingleXChainSingleVaultStateReq memory req) =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        req.superformData.amount = investAmount; // the API sets the amount slightly higher

        vault.investSingleXChainSingleVault{ value: 100 ether }(req);
        assertEq(address(vault).balance, 0);
    }

    function test_revert_MaxApyCrossChainVault_redeem_requestNotProcessed() public {
        uint256 sharesBalance = _depositAtomic(1000 * _1_USDCE, users.alice);

        skip(config.sharesLockTime);
        vm.startPrank(users.alice);
        vault.requestRedeem(vault.balanceOf(users.alice), users.alice, users.alice);
        vm.expectRevert(MaxApyCrossChainVault.RedeemNotProcessed.selector);
        vault.redeem(sharesBalance, users.alice, users.alice);
    }

    function test_MaxApyCrossChainVault_processRedeemRequest_from_idle() public {
        uint256 sharesBalance = _depositAtomic(1000 * _1_USDCE, users.alice);
        skip(config.sharesLockTime);
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
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            deductedFees: 0,
            oracle: IERC4626Oracle(address(0))
        });
        uint256 sharesBalance = _depositAtomic(1000 * _1_USDCE, users.alice);
        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);
        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);
        uint256 totalAssetsBeforeLock = vault.totalAssets();
        uint256 sharePriceBeforeLock = vault.sharePrice();
        skip(config.sharesLockTime);
        uint256 totalAssetsAfterLock = vault.totalAssets();
        uint256 sharePriceAfterLock = vault.sharePrice();
        assertEq(totalAssetsAfterLock, totalAssetsBeforeLock);
        assertEq(sharePriceAfterLock, sharePriceBeforeLock);
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
        emit Withdraw(users.alice, users.alice, users.alice, totalAssetsAfterLock, sharesBalance);
        uint256 assets = vault.redeem(sharesBalance, users.alice, users.alice);
        assertEq(assets, totalAssetsAfterLock);
    }

    function test_MaxApyCrossChainVault_processRedeemRequest_from_local_and_xchain_queue() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            deductedFees: 0,
            oracle: IERC4626Oracle(address(0))
        });
        _depositAtomic(1000 * _1_USDCE, users.alice);
        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);

        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);

        address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint64 optimismChainId = 10;

        oracle.setValues(vaultAddress, _getSharePrice(optimismChainId, vaultAddress), block.timestamp);
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId,
            vault: vaultAddress,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress),
            deductedFees: 0,
            oracle: IERC4626Oracle(address(oracle))
        });

        uint256 investAmount = 600 * _1_USDCE;
        (SingleXChainSingleVaultStateReq memory req) =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);

        req.superformData.amount = investAmount; // the API sets the amount slightly higher

        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            req
        );

        _mintSuperpositions(address(vault), superformId, shares);

        vm.startPrank(users.alice);

        vault.setSharesLockTime(0);

        uint256 aliceBalance = vault.balanceOf(users.alice);

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
            uint256 value = _getWithdrawSingleXChainSingleVaultValue(superformId, investAmount);
            sXsV.value = value;
            vm.expectEmit(true, true, true, true);
            emit ProcessRedeemRequest(users.alice, aliceBalance);
            vault.processRedeemRequest{ value: value }(users.alice, sXsV, sXmV, mXsV, mXmV);
            (,,,,,, uint128 totalDebt,) = vault.vaults(1);
            assertEq(totalDebt, 0);
            (,,,,,, totalDebt,) = vault.vaults(superformId);
            assertEq(totalDebt, 518);
        }
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalSupply(), 0);
        address receiver = vault.receivers(users.alice);
        assertEq(USDCE_BASE.balanceOf(receiver), 0);
        assertEq(USDCE_BASE.balanceOf(address(vault)), 400 * _1_USDCE);
        assertEq(vault.claimableRedeemRequest(users.alice), 400_000_207);

        deal(USDCE_BASE, address(receiver), 588 * _1_USDCE);
        skip(config.processRedeemSettlement);
        vault.fulfillSettledRequests(users.alice);
        assertEq(vault.claimableRedeemRequest(users.alice), 1000 * _1_USDCE);
        uint256 assets = vault.redeem(aliceBalance, users.alice, users.alice);
        assertEq(assets, 400 * _1_USDCE + 588 * _1_USDCE);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalIdle(), 0);
    }

    function test_MaxApyCrossChainVault_processRedeemRequest_signature() public {
        uint256 sharesBalance = _depositAtomic(1000 * _1_USDCE, users.alice);
        skip(config.sharesLockTime);
        vault.requestRedeem(vault.balanceOf(users.alice), users.alice, users.alice);
        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;
        uint256 nonce = 1;
        uint256 deadline = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = relayer.sign(
            MockSignerRelayer.SignatureParams({
                controller: users.alice,
                sXsV: sXsV,
                sXmV: sXmV,
                mXsV: mXsV,
                mXmV: mXmV,
                nonce: nonce,
                deadline: deadline
            })
        );
        vm.expectEmit(true, true, true, true);
        emit ProcessRedeemRequest(users.alice, sharesBalance);
        vault.processRedeemRequestWithSignature(
            ProcessRedeemRequestWithSignatureParams({
                controller: users.alice,
                sXsV: sXsV,
                sXmV: sXmV,
                mXsV: mXsV,
                mXmV: mXmV,
                deadline: deadline,
                v: v,
                r: r,
                s: s
            })
        );
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

    function test_revert_MaxApyCrossChainVault_report_VaultNotListed() public {
        _depositAtomic(1000 * _1_USDCE, users.alice);
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
            deductedFees: 50,
            oracle: IERC4626Oracle(address(oracle))
        });

        _depositAtomic(1000 * _1_USDCE, users.alice);

        uint256 investAmount = 600 * _1_USDCE;

        (SingleXChainSingleVaultStateReq memory req) =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        req.superformData.amount = investAmount;

        uint256 newSharesPrice = 2 * _1_USDCE;
        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);

        vm.expectEmit(true, true, true, true);
        emit Invest(investAmount);
        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            req
        );

        _mintSuperpositions(address(vault), superformId, shares);
        vm.startPrank(users.alice);
        VaultReport[] memory mockReport = new VaultReport[](1);
        mockReport[0].chainId = optimismChainId;
        mockReport[0].sharePrice = uint192(newSharesPrice);
        mockReport[0].vaultAddress = vaultAddress;

        skip(vault.SECS_PER_YEAR());
        oracle.setValues(vaultAddress, newSharesPrice, block.timestamp);

        uint256 deductedFee = 50;

        uint256 expectedPerformanceFees =
            FixedPointMathLib.mulDiv(566_695_022, (vault.performanceFee() - deductedFee), MAX_BPS);
        uint256 expectedMintedShares = vault.convertToShares(expectedPerformanceFees);

        vm.expectEmit(true, true, true, true);
        emit Report(optimismChainId, vaultAddress, 566_695_022);
        vault.report(mockReport, users.bob);
        assertEq(vault.balanceOf(config.treasury), expectedMintedShares);
        // assertApproxEq(vault.balanceOf(users.bob), 200 * _1_USDCE, 2);
    }

    function test_MaxApyCrossChainVault_addVault() public {
        address newVault = address(0x123);
        uint256 newSuperformId = 999;
        uint64 newChainId = 42;
        uint8 newDecimals = 18;
        oracle.setValues(newVault, 1 * _1_USDCE, block.timestamp);
        vm.expectEmit(true, true, true, true);
        emit AddVault(newChainId, newVault);
        vault.addVault(newChainId, newSuperformId, newVault, newDecimals, 0, IERC4626Oracle(address(oracle)));

        assertTrue(vault.isVaultListed(newVault));
    }

    function test_MaxApyCrossChainVault_addVault_ZeroSharePrice() public {
        address newVault = address(0x123);
        uint256 newSuperformId = 999;
        uint64 newChainId = 42;
        uint8 newDecimals = 18;

        vm.expectRevert();
        vault.addVault(newChainId, newSuperformId, newVault, newDecimals, 0, IERC4626Oracle(address(oracle)));
    }

    function test_revert_MaxApyCrossChainVault_addVault_alreadyListed() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        uint8 decimals = yUsdce.decimals();
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: decimals,
            deductedFees: 0,
            oracle: IERC4626Oracle(address(0))
        });
        vm.expectRevert(MaxApyCrossChainVault.VaultAlreadyListed.selector);
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: decimals,
            deductedFees: 0,
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

    function test_divestSingleDirectSingleVault() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        // Setup local vault
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            deductedFees: 0,
            oracle: IERC4626Oracle(address(0))
        });

        // Deposit and invest
        _depositAtomic(1000 * _1_USDCE, users.alice);
        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);
        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);

        // Divest
        uint256 sharesToDivest = yUsdce.balanceOf(address(vault));
        uint256 minAssetsOut = yUsdce.convertToAssets(sharesToDivest) - 1; // Allow 1 wei slippage

        vm.expectEmit(true, true, true, true);
        emit Divest(400 * _1_USDCE);

        uint256 divestAssets = vault.divestSingleDirectSingleVault(address(yUsdce), sharesToDivest, minAssetsOut);

        assertGt(divestAssets, 0);
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.totalIdle(), 1000 * _1_USDCE);
        assertEq(yUsdce.balanceOf(address(vault)), 0);
    }

    function test_divestSingleDirectMultiVault() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        MockERC4626 smUsdce = new MockERC4626(USDCE_BASE, "Sommelier USDCE", "smUSDCe", true, 0);

        // Setup two local vaults
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            deductedFees: 0,
            oracle: IERC4626Oracle(address(0))
        });

        vault.addVault({
            chainId: baseChainId,
            superformId: 2,
            vault: address(smUsdce),
            vaultDecimals: smUsdce.decimals(),
            deductedFees: 0,
            oracle: IERC4626Oracle(address(0))
        });

        // Deposit and invest in both vaults
        _depositAtomic(1000 * _1_USDCE, users.alice);
        uint256 amountPerVault = 400 * _1_USDCE;

        address[] memory vaultAddresses = new address[](2);
        vaultAddresses[0] = address(yUsdce);
        vaultAddresses[1] = address(smUsdce);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountPerVault;
        amounts[1] = amountPerVault;

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = yUsdce.previewDeposit(amountPerVault);
        minAmountsOut[1] = smUsdce.previewDeposit(amountPerVault);

        vault.investSingleDirectMultiVault(vaultAddresses, amounts, minAmountsOut);

        // Prepare divest parameters
        address[] memory divestVaults = new address[](2);
        divestVaults[0] = address(yUsdce);
        divestVaults[1] = address(smUsdce);

        uint256[] memory divestShares = new uint256[](2);
        divestShares[0] = yUsdce.balanceOf(address(vault));
        divestShares[1] = smUsdce.balanceOf(address(vault));

        uint256[] memory minDivestAmounts = new uint256[](2);
        minDivestAmounts[0] = yUsdce.convertToAssets(divestShares[0]);
        minDivestAmounts[1] = smUsdce.convertToAssets(divestShares[1]);

        // Divest from both vaults
        uint256[] memory divestAssets = vault.divestSingleDirectMultiVault(divestVaults, divestShares, minDivestAmounts);

        // Validate divest
        assertEq(divestAssets.length, 2);
        assertGt(divestAssets[0], 0);
        assertGt(divestAssets[1], 0);
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.totalIdle(), 1000 * _1_USDCE);
    }

    function test_divestSingleXChainSingleVault() public {
        address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint64 optimismChainId = 10;

        // Setup cross-chain vault
        oracle.setValues(vaultAddress, _getSharePrice(optimismChainId, vaultAddress), block.timestamp);
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId,
            vault: vaultAddress,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress),
            deductedFees: 0,
            oracle: IERC4626Oracle(address(oracle))
        });

        // Deposit and invest cross-chain
        _depositAtomic(1000 * _1_USDCE, users.alice);
        uint256 investAmount = 600 * _1_USDCE;
        SingleXChainSingleVaultStateReq memory investReq =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        investReq.superformData.amount = investAmount;

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);
        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) 
    }(
            investReq
        );
        _mintSuperpositions(address(vault), superformId, shares);

        // Prepare divest request
        SingleXChainSingleVaultStateReq memory divestReq =
            _buildDivestSingleXChainSingleVaultParams(superformId, investAmount);

        // Execute divest
        vm.expectEmit(true, true, true, true);
        emit Divest(investAmount);

        vm.startPrank(users.alice);
        vault.divestSingleXChainSingleVault{ value: _getDivestSingleXChainSingleVaultValue(superformId, shares) }(
            divestReq
        );

        // // // Validate state after divest initiation
        // assertEq(vault.totalIdle(), investAmount, "Idle should include divested amount");
        // assertEq(vault._pendingXChainWithdraws(superformId), investAmount, "Should track pending withdrawal");
    }

    // -- Fee Logic Tests --

    // function test_report_managementFees() public {
    //     // Setup vault with assets
    //     _depositAtomic(1000 * _1_USDCE, users.alice);

    //     // Skip one year
    //     skip(vault.SECS_PER_YEAR());

    //     // Calculate expected management fee
    //     uint256 totalAssets = vault.totalAssets();
    //     uint256 expectedManagementFee = (totalAssets * vault.managementFee()) / vault.MAX_BPS();

    //     // Create report with no price change
    //     VaultReport[] memory reports = new VaultReport[](0);

    //     // Capture treasury balance before
    //     uint256 treasuryBalanceBefore = vault.balanceOf(config.treasury);

    //     // Report and distribute fees
    //     vault.report(reports, users.bob);

    //     // Validate management fee
    //     uint256 actualFee = vault.balanceOf(config.treasury) - treasuryBalanceBefore;
    //     assertApproxEqRel(
    //         actualFee,
    //         expectedManagementFee,
    //         1e16, // 1% tolerance
    //         "Management fee calculation incorrect"
    //     );
    // }

    // function test_report_feeDeduction() public {
    //     address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
    //     uint256 superformId = EXACTLY_USDC_VAULT_ID_OPTIMISM;
    //     uint64 optimismChainId = 10;

    //     // Setup vault with deducted fees
    //     uint16 deductedFees = 1000; // 10%
    //     oracle.setValues(vaultAddress, _getSharePrice(optimismChainId, vaultAddress), block.timestamp);
    //     vault.addVault({
    //         chainId: optimismChainId,
    //         superformId: superformId,
    //         vault: vaultAddress,
    //         vaultDecimals: _getDecimals(optimismChainId, vaultAddress),
    //         deductedFees: deductedFees,
    //         oracle: IERC4626Oracle(address(oracle))
    //     });

    //     _depositAtomic(1000 * _1_USDCE, users.alice);

    //     // Invest and generate profit
    //     uint256 investAmount = 600 * _1_USDCE;
    //     SingleXChainSingleVaultStateReq memory req =
    //         _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

    //     uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);
    //     vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount)
    // }(
    //         req
    //     );
    //     _mintSuperpositions(address(vault), superformId, shares);

    //     // Skip time and simulate profit
    //     skip(vault.SECS_PER_YEAR());
    //     uint256 newSharePrice = 2 * _1_USDCE;

    //     // Validate oracle fee
    //     uint256 actualOracleFee = vault.balanceOf(users.bob) - oracleBalanceBefore;
    //     assertApproxEqRel(
    //         actualOracleFee,
    //         expectedOracleFee,
    //         1e16, // 1% tolerance
    //         "Oracle fee calculation incorrect"
    //     );
    // }
}
