// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { BaseVaultTest } from "../base/BaseVaultTest.t.sol";

import { MaxApyCrossChainVaultEvents } from "../helpers/MaxApyCrossChainVaultEvents.sol";
import { SuperformActions } from "../helpers/SuperformActions.sol";
import { _1_USDCE } from "../helpers/Tokens.sol";
import { MockERC4626Oracle } from "../helpers/mock/MockERC4626Oracle.sol";
import { MockSignerRelayer } from "../helpers/mock/MockSignerRelayer.sol";
import { Test, console2 } from "forge-std/Test.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { ERC4626, ERC7540, MaxApyCrossChainVault } from "src/MaxApyCrossChainVault.sol";

import {
    EXACTLY_USDC_VAULT_ID_OPTIMISM,
    EXACTLY_USDC_VAULT_OPTIMISM,
    LAYERZERO_ULTRALIGHT_NODE_POLYGON,
    SUPERFORM_CORE_STATE_REGISTRY,
    SUPERFORM_LAYERZERO_ENDPOINT_POLYGON,
    SUPERFORM_LAYERZERO_IMPLEMENTATION_POLYGON,
    SUPERFORM_LAYERZERO_V2_IMPLEMENTATION_POLYGON,
    SUPERFORM_PAYMASTER_POLYGON,
    SUPERFORM_PAYMENT_HELPER_POLYGON,
    SUPERFORM_ROUTER_POLYGON,
    SUPERFORM_SUPEREGISTRY_POLYGON,
    SUPERFORM_SUPERPOSITIONS_POLYGON,
    USDCE_POLYGON,
    YEARN_USDCE_LENDER_VAULT_POLYGON,
    YEARN_USDCE_VAULT_POLYGON
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

    MaxApyCrossChainVault public vault;
    ERC4626 public yUsdce;
    MockERC4626Oracle public oracle;
    MockSignerRelayer public relayer;
    uint256 public yUsdceSharePrice;

    function _setUpTestEnvironment() private {
        yUsdce = ERC4626(YEARN_USDCE_VAULT_POLYGON);

        config = polygonUsdceVaultConfig();
        relayer = new MockSignerRelayer(0xA111ce);
        config.signerRelayer = relayer.signerAddress();

        vault = new MaxApyCrossChainVault(config);
        console2.log("VAULT ADDRESS :", address(vault));
        console2.log("ALICE :", users.alice);
        oracle = new MockERC4626Oracle();
        yUsdceSharePrice = yUsdce.convertToAssets(10 ** yUsdce.decimals());
        vault.grantRoles(users.alice, vault.MANAGER_ROLE());
        vault.grantRoles(users.alice, vault.ORACLE_ROLE());
        vault.grantRoles(users.alice, vault.RELAYER_ROLE());
        vault.grantRoles(users.alice, vault.EMERGENCY_ADMIN_ROLE());
        USDCE_POLYGON.safeApprove(address(vault), type(uint256).max);
    }

    function _setupContractLabels() private {
        vm.label(SUPERFORM_SUPEREGISTRY_POLYGON, "SuperRegistry");
        vm.label(SUPERFORM_SUPERPOSITIONS_POLYGON, "SuperPositions");
        vm.label(SUPERFORM_PAYMENT_HELPER_POLYGON, "PaymentHelper");
        vm.label(SUPERFORM_PAYMASTER_POLYGON, "PayMaster");
        vm.label(SUPERFORM_LAYERZERO_V2_IMPLEMENTATION_POLYGON, "LayerZeroV2Implementation");
        vm.label(SUPERFORM_LAYERZERO_IMPLEMENTATION_POLYGON, "LayerZeroImplementation");
        vm.label(SUPERFORM_LAYERZERO_ENDPOINT_POLYGON, "LayerZeroEndpoint");
        vm.label(SUPERFORM_CORE_STATE_REGISTRY, "CoreStateRegistry");
        vm.label(LAYERZERO_ULTRALIGHT_NODE_POLYGON, "UltraLightNode");
        vm.label(SUPERFORM_ROUTER_POLYGON, "SuperRouter");
        vm.label(address(vault), "MaxApyCrossChainVault");
        vm.label(USDCE_POLYGON, "USDC");
        vm.label(address(oracle), "SharePriceOracle");
        vm.label(address(relayer), "Relayer");
    }

    function setUp() public override {
        super._setUp("POLYGON", 64_270_724);
        super.setUp();

        _setUpTestEnvironment();
        _setupContractLabels();
    }

    function test_MaxApyCrossChainVault_initialization() public view {
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.asset(), USDCE_POLYGON);
        assertEq(vault.decimals(), 6);
        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.managementFee(), 100);
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
        vault.addVault({
            chainId: 137,
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
            deductedFees: 0,
            oracle: IERC4626Oracle(address(0))
        });
        ERC4626 yUsdceLender = ERC4626(YEARN_USDCE_LENDER_VAULT_POLYGON);
        vault.addVault({
            chainId: 137,
            superformId: 2,
            vault: address(yUsdceLender),
            vaultDecimals: yUsdceLender.decimals(),
            deductedFees: 0,
            oracle: IERC4626Oracle(address(0))
        });

        _depositAtomic(1000 * _1_USDCE, users.alice);

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
            deductedFees: 0,
            oracle: IERC4626Oracle(address(oracle))
        });

        _depositAtomic(1000 * _1_USDCE, users.alice);

        uint256 investAmount = 600 * _1_USDCE;
        (SingleXChainSingleVaultStateReq memory req) =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);

        vm.startPrank(users.alice);
        vm.expectEmit(true, true, true, true);
        emit Invest(investAmount);
        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            req
        );
        assertEq(USDCE_POLYGON.balanceOf(address(vault)), 400 * _1_USDCE);
        assertEq(vault.totalAssets(), 1000 * _1_USDCE);
        assertEq(vault.totalXChainAssets(), 0);
        assertEq(vault.totalLocalAssets(), 400 * _1_USDCE);
        assertEq(vault.totalWithdrawableAssets(), 400 * _1_USDCE);
        _mintSuperpositions(address(vault), superformId, shares);
        assertEq(vault.totalAssets(), 999_999_482);
        // assertEq(vault.totalWithdrawableAssets(), 999_999_482);
        // assertEq(vault.totalXChainAssets(), 599_999_482);
        // assertEq(vault.totalLocalAssets(), 400 * _1_USDCE);
        // assertEq(vault.totalIdle(), 400 * _1_USDCE);
        // assertEq(config.superPositions.balanceOf(address(vault), superformId), shares);
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
        vault.addVault({
            chainId: 137,
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
        assertEq(vault.totalAssets(), 1);
        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.claimableRedeemRequest(users.alice), sharesBalance);
        assertEq(vault.pendingRedeemRequest(users.alice), 0);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(users.alice, users.alice, users.alice, totalAssetsAfterLock - 2, sharesBalance);
        uint256 assets = vault.redeem(sharesBalance, users.alice, users.alice);
        assertEq(assets, totalAssetsAfterLock - 2);
    }

    function test_MaxApyCrossChainVault_processRedeemRequest_from_local_and_xchain_queue() public {
        vault.addVault({
            chainId: 137,
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
            assertEq(totalDebt, 1);
            (,,,,,, totalDebt,) = vault.vaults(superformId);
            assertEq(totalDebt, 0);
        }
        // assertEq(vault.totalAssets(), 0);
        // assertEq(vault.totalSupply(), 0);
        // address receiver = vault.receivers(users.alice);
        // assertEq(USDCE_POLYGON.balanceOf(receiver), 0);
        // assertEq(USDCE_POLYGON.balanceOf(address(vault)), 399_999_999);
        // assertEq(vault.claimableRedeemRequest(users.alice), 400_000_206);

        // deal(USDCE_POLYGON, address(receiver), 588 * _1_USDCE);
        // skip(config.processRedeemSettlement);
        // assertEq(vault.claimableRedeemRequest(users.alice), 1000 * _1_USDCE);
        // uint256 assets = vault.redeem(aliceBalance, users.alice, users.alice);
        // assertEq(assets, 399_999_999 + 588 * _1_USDCE);
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

    function test_revert_MaxApyCrossChainVault_redeem_requestNotSettled() public {
        vault.addVault({
            chainId: 137,
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
            vault.processRedeemRequest{ value: value }(users.alice, sXsV, sXmV, mXsV, mXmV);
        }

        address receiver = vault.receivers(users.alice);

        deal(USDCE_POLYGON, address(receiver), 588 * _1_USDCE);
        vm.expectRevert(MaxApyCrossChainVault.RequestNotSettled.selector);
        vault.redeem(aliceBalance, users.alice, users.alice);
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
            deductedFees: 0,
            oracle: IERC4626Oracle(address(oracle))
        });

        _depositAtomic(1000 * _1_USDCE, users.alice);

        uint256 investAmount = 600 * _1_USDCE;

        (SingleXChainSingleVaultStateReq memory req) =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

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

        vm.expectEmit(true, true, true, true);
        emit Report(optimismChainId, vaultAddress, 566_695_022);
        vault.report(mockReport, users.bob);
        assertApproxEq(vault.balanceOf(config.treasury), 200 * _1_USDCE, 2);
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
        uint8 decimals = yUsdce.decimals();
        vault.addVault({
            chainId: 137,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: decimals,
            deductedFees: 0,
            oracle: IERC4626Oracle(address(0))
        });
        vm.expectRevert(MaxApyCrossChainVault.VaultAlreadyListed.selector);
        vault.addVault({
            chainId: 137,
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

    function _depositAtomic(uint256 assets, address receiver) private returns (uint256 _shares) {
        bytes[] memory callDatas = new bytes[](2);
        callDatas[0] =
            abi.encodeWithSelector(MaxApyCrossChainVault.requestDeposit.selector, assets, receiver, users.alice);
        callDatas[1] = abi.encodeWithSignature("deposit(uint256,address)", assets, receiver);
        bytes[] memory returnData = vault.multicall(callDatas);
        return abi.decode(returnData[1], (uint256));
    }

    function _mintAtomic(uint256 shares, address receiver) private returns (uint256 _assets) {
        bytes[] memory callDatas = new bytes[](2);
        uint256 assets = vault.convertToAssets(shares);
        callDatas[0] =
            abi.encodeWithSelector(MaxApyCrossChainVault.requestDeposit.selector, assets, receiver, users.alice);
        callDatas[1] = abi.encodeWithSignature("mint(uint256,address)", shares, receiver);
        bytes[] memory returnData = vault.multicall(callDatas);
        return abi.decode(returnData[1], (uint256));
    }

    function test_divestSingleDirectSingleVault() public {
        // Setup local vault
        vault.addVault({
            chainId: 137,
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
        emit Divest(400 * _1_USDCE - 1);

        uint256 divestAssets = vault.divestSingleDirectSingleVault(address(yUsdce), sharesToDivest, minAssetsOut);

        // Validate divest
        assertGt(divestAssets, 0, "Should have divested assets");
        assertEq(vault.totalDebt(), 0, "Should have no remaining debt");
        assertEq(vault.totalIdle(), 1000 * _1_USDCE - 1, "Should have returned assets to idle");
        assertEq(yUsdce.balanceOf(address(vault)), 0, "Should have no remaining vault shares");
    }

    function test_revert_divestSingleDirectSingleVault_InsufficientAssets() public {
        vault.addVault({
            chainId: 137,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            deductedFees: 0,
            oracle: IERC4626Oracle(address(0))
        });

        _depositAtomic(1000 * _1_USDCE, users.alice);
        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);
        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);

        uint256 sharesToDivest = yUsdce.balanceOf(address(vault));
        uint256 minAssetsOut = yUsdce.convertToAssets(sharesToDivest) + 1; // Require more than possible

        vm.expectRevert(MaxApyCrossChainVault.InsufficientAssets.selector);
        vault.divestSingleDirectSingleVault(address(yUsdce), sharesToDivest, minAssetsOut);
    }

    // -- Divest Single Direct Multi Vault Tests --

    function test_divestSingleDirectMultiVault() public {
        // Setup two local vaults
        vault.addVault({
            chainId: 137,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            deductedFees: 0,
            oracle: IERC4626Oracle(address(0))
        });

        ERC4626 yUsdceLender = ERC4626(YEARN_USDCE_LENDER_VAULT_POLYGON);
        vault.addVault({
            chainId: 137,
            superformId: 2,
            vault: address(yUsdceLender),
            vaultDecimals: yUsdceLender.decimals(),
            deductedFees: 0,
            oracle: IERC4626Oracle(address(0))
        });

        // Deposit and invest in both vaults
        _depositAtomic(1000 * _1_USDCE, users.alice);
        uint256 amountPerVault = 400 * _1_USDCE;

        address[] memory vaultAddresses = new address[](2);
        vaultAddresses[0] = address(yUsdce);
        vaultAddresses[1] = address(yUsdceLender);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountPerVault;
        amounts[1] = amountPerVault;

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = yUsdce.previewDeposit(amountPerVault);
        minAmountsOut[1] = yUsdceLender.previewDeposit(amountPerVault);

        vault.investSingleDirectMultiVault(vaultAddresses, amounts, minAmountsOut);

        // Prepare divest parameters
        address[] memory divestVaults = new address[](2);
        divestVaults[0] = address(yUsdce);
        divestVaults[1] = address(yUsdceLender);

        uint256[] memory divestShares = new uint256[](2);
        divestShares[0] = yUsdce.balanceOf(address(vault));
        divestShares[1] = yUsdceLender.balanceOf(address(vault));

        uint256[] memory minDivestAmounts = new uint256[](2);
        minDivestAmounts[0] = yUsdce.convertToAssets(divestShares[0]);
        minDivestAmounts[1] = yUsdceLender.convertToAssets(divestShares[1]);

        // Divest from both vaults
        uint256[] memory divestAssets = vault.divestSingleDirectMultiVault(divestVaults, divestShares, minDivestAmounts);

        // Validate divest
        assertEq(divestAssets.length, 2, "Should have divested from both vaults");
        assertGt(divestAssets[0], 0, "Should have divested assets from first vault");
        assertGt(divestAssets[1], 0, "Should have divested assets from second vault");
        assertEq(vault.totalDebt(), 0, "Should have no remaining debt");
        assertApproxEqRel(
            vault.totalIdle(),
            1000 * _1_USDCE,
            1e16, // 1% tolerance
            "Should have returned all assets to idle"
        );
    }

    // -- Cross-Chain Divest Tests --
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

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);
        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
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

        // // Validate state after divest initiation
        // assertEq(vault.totalIdle(), investAmount, "Idle should include divested amount");
        // assertEq(vault._pendingXChainWithdraws(superformId), investAmount, "Should track pending withdrawal");
    }

    // -- Fee Logic Tests --

    function test_report_managementFees() public {
        // Setup vault with assets
        _depositAtomic(1000 * _1_USDCE, users.alice);

        // Skip one year
        skip(vault.SECS_PER_YEAR());

        // Calculate expected management fee
        uint256 totalAssets = vault.totalAssets();
        uint256 expectedManagementFee = (totalAssets * vault.managementFee()) / vault.MAX_BPS();

        // Create report with no price change
        VaultReport[] memory reports = new VaultReport[](0);

        // Capture treasury balance before
        uint256 treasuryBalanceBefore = vault.balanceOf(config.treasury);

        // Report and distribute fees
        vault.report(reports, users.bob);

        // Validate management fee
        uint256 actualFee = vault.balanceOf(config.treasury) - treasuryBalanceBefore;
        assertApproxEqRel(
            actualFee,
            expectedManagementFee,
            1e16, // 1% tolerance
            "Management fee calculation incorrect"
        );
    }

    function test_report_performanceFees() public {
        address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint64 optimismChainId = 10;

        // Setup vault with investment
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

        // Invest in vault
        uint256 investAmount = 600 * _1_USDCE;
        SingleXChainSingleVaultStateReq memory req =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);
        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            req
        );
        _mintSuperpositions(address(vault), superformId, shares);

        // Skip time and simulate profit
        skip(vault.SECS_PER_YEAR());
        uint256 newSharePrice = 2 * _1_USDCE; // 100% increase

        // Create report with profit
        VaultReport[] memory reports = new VaultReport[](1);
        reports[0].chainId = optimismChainId;
        reports[0].sharePrice = uint192(newSharePrice);
        reports[0].vaultAddress = vaultAddress;

        // Set oracle price
        oracle.setValues(vaultAddress, newSharePrice, block.timestamp);

        // Capture balances before
        uint256 treasuryBalanceBefore = vault.balanceOf(config.treasury);

        vm.startPrank(users.alice);
        // Report profit and distribute fees
        vault.report(reports, users.bob);

        // Calculate expected performance fee
        uint256 profit = investAmount; // 100% return
        uint256 expectedPerformanceFee = (profit * vault.performanceFee()) / vault.MAX_BPS();

        // Validate performance fee
        uint256 actualFee = vault.balanceOf(config.treasury) - treasuryBalanceBefore;
        assertApproxEqRel(
            actualFee,
            expectedPerformanceFee,
            1e16, // 1% tolerance
            "Performance fee calculation incorrect"
        );
    }

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
