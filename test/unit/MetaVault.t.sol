// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { BaseVaultTest } from "../base/BaseVaultTest.t.sol";

import { MetaVaultEvents } from "../helpers/MetaVaultEvents.sol";
import { SuperformActions } from "../helpers/SuperformActions.sol";
import { _1_USDCE } from "../helpers/Tokens.sol";

import { MockERC4626 } from "../helpers/mock/MockERC4626.sol";
import { MockERC4626Oracle } from "../helpers/mock/MockERC4626Oracle.sol";
import { MockSignerRelayer } from "../helpers/mock/MockSignerRelayer.sol";
import { Test, console2 } from "forge-std/Test.sol";

import { IMetaVault, ISuperformGateway } from "interfaces/Lib.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

import { ERC7540 } from "lib/Lib.sol";
import { LibString } from "solady/utils/LibString.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { MetaVaultWrapper } from "../helpers/mock/MetaVaultWrapper.sol";
import { ERC7540Engine } from "modules/Lib.sol";
import { ERC4626, MetaVault } from "src/MetaVault.sol";

import { ERC20Receiver, SuperformGateway } from "crosschain/Lib.sol";
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
import { ISharePriceOracle } from "src/interfaces/Lib.sol";
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

contract MetaVaultTest is BaseVaultTest, SuperformActions, MetaVaultEvents {
    using SafeTransferLib for address;
    using LibString for bytes;

    MockERC4626Oracle public oracle;
    ERC7540Engine engine;
    MockSignerRelayer public relayer;
    SuperformGateway public gateway;
    uint64 baseChainId = 8453;

    function _setUpTestEnvironment() private {
        config = baseChainUsdceVaultConfig();
        relayer = MockSignerRelayer(address(config.signerRelayer));
        config.signerRelayer = relayer.signerAddress();

        vault = IMetaVault(address(new MetaVaultWrapper(config)));
        engine = new ERC7540Engine();
        gateway = deployGatewayBase(address(vault), users.alice);
        vault.setGateway(address(gateway));
        vault.addFunction(ERC7540Engine.processRedeemRequest.selector, address(engine), false);
        //vault.addFunction(ERC7540Engine.processRedeemRequestWithSignature.selector, address(engine), false);
        vault.addFunction(ERC7540Engine.previewWithdrawalRoute.selector, address(engine), false);
        gateway.grantRoles(users.alice, gateway.RELAYER_ROLE());
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
        vm.label(address(vault), "MetaVault");
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

    function test_MetaVault_initialization() public view {
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.asset(), USDCE_BASE);
        assertEq(vault.decimals(), 6);
        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.managementFee(), 0);
        assertEq(vault.performanceFee(), 2000);
        assertEq(vault.oracleFee(), 0);
        assertEq(vault.hurdleRate(), 600);
        assertEq(vault.lastReport(), block.timestamp);
        assertEq(vault.treasury(), config.treasury);
    }

    function test_MetaVault_depositAtomic() public {
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

    function test_MetaVault_mintAtomic() public {
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

    function test_MetaVault_investSingleDirectSingleVault() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);

        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            deductedFees: 0,
            oracle: ISharePriceOracle(address(0))
        });
        _depositAtomic(1000 * _1_USDCE, users.alice);
        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);

        vm.expectRevert(MetaVault.InsufficientAssets.selector);
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

    function test_MetaVault_investSingleDirectMultiVault() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        MockERC4626 smUsdce = new MockERC4626(USDCE_BASE, "Sommelier USDCE", "smUSDCe", true, 0);

        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            deductedFees: 0,
            oracle: ISharePriceOracle(address(0))
        });
        vault.addVault({
            chainId: baseChainId,
            superformId: 2,
            vault: address(smUsdce),
            vaultDecimals: smUsdce.decimals(),
            deductedFees: 0,
            oracle: ISharePriceOracle(address(0))
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

        vm.expectRevert(MetaVault.InsufficientAssets.selector);
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

    function test_MetaVault_investSingleXChainSingleVault() public {
        address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint64 optimismChainId = 10;

        oracle.setValues(
            optimismChainId, vaultAddress, _getSharePrice(optimismChainId, vaultAddress), block.timestamp, users.bob
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId,
            vault: vaultAddress,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress),
            deductedFees: 0,
            oracle: ISharePriceOracle(address(oracle))
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
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId, shares);
        assertEq(vault.totalAssets(), 999_999_482);
        assertEq(vault.totalWithdrawableAssets(), 999_999_482);
        assertEq(vault.totalXChainAssets(), 599_999_482);
        assertEq(vault.totalLocalAssets(), 400 * _1_USDCE);
        assertEq(vault.totalIdle(), 400 * _1_USDCE);
        assertEq(config.superPositions.balanceOf(address(vault), superformId), shares);
    }

    function test_MetaVault_refund_gas() public {
        address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint64 optimismChainId = 10;

        oracle.setValues(
            optimismChainId, vaultAddress, _getSharePrice(optimismChainId, vaultAddress), block.timestamp, users.bob
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId,
            vault: vaultAddress,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress),
            deductedFees: 0,
            oracle: ISharePriceOracle(address(oracle))
        });

        _depositAtomic(1000 * _1_USDCE, users.alice);

        uint256 investAmount = 600 * _1_USDCE;
        (SingleXChainSingleVaultStateReq memory req) =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        req.superformData.amount = investAmount; // the API sets the amount slightly higher

        vault.investSingleXChainSingleVault{ value: 100 ether }(req);
        assertEq(address(vault).balance, 0);
    }

    function test_MetaVault_processRedeemRequest_from_idle() public {
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

    function test_MetaVault_processRedeemRequest_from_local_queue() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            deductedFees: 0,
            oracle: ISharePriceOracle(address(0))
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

    function test_MetaVault_processRedeemRequest_from_local_and_xchain_queue() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            deductedFees: 0,
            oracle: ISharePriceOracle(address(0))
        });
        _depositAtomic(1000 * _1_USDCE, users.alice);
        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);

        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);

        address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint64 optimismChainId = 10;

        oracle.setValues(
            optimismChainId, vaultAddress, _getSharePrice(optimismChainId, vaultAddress), block.timestamp, users.bob
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId,
            vault: vaultAddress,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress),
            deductedFees: 0,
            oracle: ISharePriceOracle(address(oracle))
        });

        uint256 investAmount = 600 * _1_USDCE;
        (SingleXChainSingleVaultStateReq memory req) =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);

        req.superformData.amount = investAmount; // the API sets the amount slightly higher

        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            req
        );

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId, shares);

        vm.startPrank(users.alice);

        vault.setSharesLockTime(0);

        uint256 aliceBalance = vault.balanceOf(users.alice);

        vault.requestRedeem(vault.balanceOf(users.alice), users.alice, users.alice);

        {
            oracle.setValues(
                optimismChainId, vaultAddress, _getSharePrice(optimismChainId, vaultAddress), block.timestamp, users.bob
            );
        }

        {
            bytes32 requestId;
            SingleXChainSingleVaultWithdraw memory sXsV;
            SingleXChainMultiVaultWithdraw memory sXmV;
            MultiXChainSingleVaultWithdraw memory mXsV;
            MultiXChainMultiVaultWithdraw memory mXmV;

            (sXsV.ambIds, sXsV.outputAmount, sXsV.maxSlippage, sXsV.liqRequest, sXsV.hasDstSwap) =
                _buildWithdrawSingleXChainSingleVaultParams(superformId, investAmount);
            sXsV.outputAmount = 588 * _1_USDCE;
            uint256 value = _getWithdrawSingleXChainSingleVaultValue(superformId, investAmount);
            sXsV.value = value;
            vm.expectEmit(true, true, true, true);
            emit ProcessRedeemRequest(users.alice, aliceBalance);
            vault.processRedeemRequest{ value: value }(users.alice, sXsV, sXmV, mXsV, mXmV);
            requestId = gateway.getRequestsQueue()[0];
            (,,,,,, uint128 totalDebt,) = vault.vaults(1);
            assertEq(totalDebt, 0);
            (,,,,,, totalDebt,) = vault.vaults(superformId);
            assertEq(totalDebt, 0);
            assertEq(vault.totalAssets(), 0);
            assertEq(vault.totalSupply(), 0);
            address receiver = gateway.getReceiver(requestId);
            assertEq(USDCE_BASE.balanceOf(receiver), 0);
            assertEq(USDCE_BASE.balanceOf(address(vault)), 400 * _1_USDCE);
            assertEq(vault.claimableRedeemRequest(users.alice), 400_000_207);

            deal(USDCE_BASE, address(receiver), 588 * _1_USDCE);
            gateway.settleLiquidation(requestId, false);
        }
        assertEq(vault.claimableRedeemRequest(users.alice), 999_999_689);
        uint256 assets = vault.redeem(999_999_689, users.alice, users.alice);
        assertEq(assets, 400 * _1_USDCE + 588 * _1_USDCE);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalIdle(), 0);
    }

    function test_MetaVault_processRedeemRequest_from_local_and_xchain_queue_failed() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            deductedFees: 0,
            oracle: ISharePriceOracle(address(0))
        });
        _depositAtomic(1000 * _1_USDCE, users.alice);
        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);

        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);

        address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint64 optimismChainId = 10;

        oracle.setValues(
            optimismChainId, vaultAddress, _getSharePrice(optimismChainId, vaultAddress), block.timestamp, users.bob
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId,
            vault: vaultAddress,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress),
            deductedFees: 0,
            oracle: ISharePriceOracle(address(oracle))
        });

        uint256 investAmount = 600 * _1_USDCE;
        (SingleXChainSingleVaultStateReq memory req) =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);

        req.superformData.amount = investAmount;

        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            req
        );

        _mintSuperpositions(address(gateway.recoveryAddress()), superformId, shares);

        vm.startPrank(users.alice);

        vault.setSharesLockTime(0);

        uint256 aliceBalance = vault.balanceOf(users.alice);

        vault.requestRedeem(vault.balanceOf(users.alice), users.alice, users.alice);

        {
            oracle.setValues(
                optimismChainId, vaultAddress, _getSharePrice(optimismChainId, vaultAddress), block.timestamp, users.bob
            );
        }

        {
            bytes32 requestId;
            SingleXChainSingleVaultWithdraw memory sXsV;
            SingleXChainMultiVaultWithdraw memory sXmV;
            MultiXChainSingleVaultWithdraw memory mXsV;
            MultiXChainMultiVaultWithdraw memory mXmV;

            (sXsV.ambIds, sXsV.outputAmount, sXsV.maxSlippage, sXsV.liqRequest, sXsV.hasDstSwap) =
                _buildWithdrawSingleXChainSingleVaultParams(superformId, investAmount);
            sXsV.outputAmount = 588 * _1_USDCE;
            uint256 value = _getWithdrawSingleXChainSingleVaultValue(superformId, investAmount);
            sXsV.value = value;

            vm.expectEmit(true, true, true, true);
            emit ProcessRedeemRequest(users.alice, aliceBalance);
            vault.processRedeemRequest{ value: value }(users.alice, sXsV, sXmV, mXsV, mXmV);
            requestId = gateway.getRequestsQueue()[0];

            (,,,,,, uint128 totalDebt,) = vault.vaults(1);
            assertEq(totalDebt, 0);
            (,,,,,, totalDebt,) = vault.vaults(superformId);
            assertEq(totalDebt, 0);
            assertEq(vault.totalAssets(), 0);
            assertEq(vault.totalSupply(), 0);

            address receiver = gateway.getReceiver(requestId);
            assertEq(USDCE_BASE.balanceOf(receiver), 0);
            assertEq(USDCE_BASE.balanceOf(address(vault)), 400 * _1_USDCE);
            assertEq(vault.claimableRedeemRequest(users.alice), 400_000_207);

            // Instead of settling, simulate failure by minting superpositions back
            _mintSuperpositions(receiver, superformId, shares);

            // Verify state after failed redeem
            assertEq(config.superPositions.balanceOf(address(vault), superformId), shares);
            (,,,,,, uint128 vaultDebt,) = vault.vaults(superformId);
            assertApproxEq(vaultDebt, 600 * _1_USDCE, _1_USDCE);
            assertEq(vault.totalDebt(), vaultDebt);
            assertApproxEq(vault.totalXChainAssets(), 600 * _1_USDCE, _1_USDCE);
        }
    }

    function test_MetaVault_addVault() public {
        address newVault = address(0x123);
        uint256 newSuperformId = 999;
        uint64 newChainId = 42;
        uint8 newDecimals = 18;
        oracle.setValues(newChainId, address(newVault), 1e6, block.timestamp, address(1));
        vm.expectEmit(true, true, true, true);
        emit AddVault(newChainId, newVault);
        vault.addVault(newChainId, newSuperformId, newVault, newDecimals, 0, ISharePriceOracle(address(oracle)));

        assertTrue(vault.isVaultListed(newVault));
    }

    function test_MetaVault_addVault_ZeroSharePrice() public {
        address newVault = address(0x123);
        uint256 newSuperformId = 999;
        uint64 newChainId = 42;
        uint8 newDecimals = 18;

        vm.expectRevert();
        vault.addVault(newChainId, newSuperformId, newVault, newDecimals, 0, ISharePriceOracle(address(oracle)));
    }

    function test_revert_MetaVault_addVault_alreadyListed() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        uint8 decimals = yUsdce.decimals();
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: decimals,
            deductedFees: 0,
            oracle: ISharePriceOracle(address(0))
        });
        vm.expectRevert(MetaVault.VaultAlreadyListed.selector);
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: decimals,
            deductedFees: 0,
            oracle: ISharePriceOracle(address(0))
        });
    }

    function test_MetaVault_setSharesLockTime() public {
        uint24 newLockTime = 60 days;

        vm.expectEmit(true, true, true, true);
        emit SetSharesLockTime(newLockTime);
        vault.setSharesLockTime(newLockTime);

        assertEq(vault.sharesLockTime(), newLockTime);
    }

    function test_MetaVault_setManagementFee() public {
        uint16 newFee = 3000;

        vm.expectEmit(true, true, true, true);
        emit SetManagementFee(newFee);
        vault.setManagementFee(newFee);

        assertEq(vault.managementFee(), newFee);
    }

    function test_MetaVault_setOracleFee() public {
        uint16 newFee = 2500;

        vm.expectEmit(true, true, true, true);
        emit SetOracleFee(newFee);
        vault.setOracleFee(newFee);

        assertEq(vault.oracleFee(), newFee);
    }

    function test_revert_MetaVault_emergencyShutdown() public {
        vault.setEmergencyShutdown(true);

        vm.expectRevert(MetaVault.VaultShutdown.selector);
        vault.requestDeposit(100 * _1_USDCE, users.alice, users.alice);
    }

    function test_revert_MetaVault_invalidController() public {
        uint256 amount = 100 * _1_USDCE;
        vault.requestDeposit(amount, users.alice, users.alice);

        vm.startPrank(users.bob);
        vm.expectRevert(ERC7540.InvalidController.selector);
        vault.deposit(amount, users.bob, users.alice);
    }

    function test_MetaVault_setOperator() public {
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

    function test_revert_MetaVault_setOperator_invalidOperator() public {
        vm.expectRevert(ERC7540.InvalidOperator.selector);
        vault.setOperator(users.alice, true);
    }

    function test_notifyFailedInvest() public {
        address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint64 optimismChainId = 10;

        // Setup cross-chain vault
        oracle.setValues(
            optimismChainId, vaultAddress, _getSharePrice(optimismChainId, vaultAddress), block.timestamp, users.bob
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId,
            vault: vaultAddress,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress),
            deductedFees: 0,
            oracle: ISharePriceOracle(address(oracle))
        });

        // Deposit and invest cross-chain
        _depositAtomic(1000 * _1_USDCE, users.alice);
        uint256 investAmount = 600 * _1_USDCE;
        SingleXChainSingleVaultStateReq memory investReq =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        investReq.superformData.amount = investAmount;

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);
        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            investReq
        );

        // Verify initial state
        assertEq(vault.totalAssets(), 1000 * _1_USDCE);
        assertEq(vault.totalIdle(), 400 * _1_USDCE);
        assertEq(gateway.totalpendingXChainInvests(), 600 * _1_USDCE);

        deal(USDCE_BASE, users.alice, investAmount);
        // Simulate failed investment
        vm.startPrank(users.alice);
        USDCE_BASE.safeApprove(address(gateway), type(uint256).max);
        gateway.notifyFailedInvest(superformId, investAmount);
        vm.stopPrank();

        // Verify state after failed invest
        assertEq(gateway.totalpendingXChainInvests(), 0);
        assertEq(vault.totalAssets(), 1000 * _1_USDCE);
        assertEq(vault.totalIdle(), 1000 * _1_USDCE);
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
            oracle: ISharePriceOracle(address(0))
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
            oracle: ISharePriceOracle(address(0))
        });

        vault.addVault({
            chainId: baseChainId,
            superformId: 2,
            vault: address(smUsdce),
            vaultDecimals: smUsdce.decimals(),
            deductedFees: 0,
            oracle: ISharePriceOracle(address(0))
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
        oracle.setValues(
            optimismChainId, vaultAddress, _getSharePrice(optimismChainId, vaultAddress), block.timestamp, users.bob
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId,
            vault: vaultAddress,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress),
            deductedFees: 0,
            oracle: ISharePriceOracle(address(oracle))
        });

        // Deposit and invest cross-chain
        _depositAtomic(1000 * _1_USDCE, users.alice);
        uint256 investAmount = 600 * _1_USDCE;
        SingleXChainSingleVaultStateReq memory investReq =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        investReq.superformData.amount = investAmount;

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);
        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            investReq
        );
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId, shares);

        uint256 value = _getDivestSingleXChainSingleVaultValue(superformId, investAmount);

        // Prepare divest request
        SingleXChainSingleVaultStateReq memory divestReq =
            _buildDivestSingleXChainSingleVaultParams(superformId, investAmount);

        VaultReport memory report = oracle.getLatestSharePrice(optimismChainId, vaultAddress);
        uint256 lastSharePrice = report.sharePrice;
        uint256 expectedDivestedValue = lastSharePrice * shares / 10 ** 6;
        divestReq.superformData.outputAmount = expectedDivestedValue;
        // Execute divest
        vm.expectEmit(true, true, true, true);
        emit Divest(expectedDivestedValue);

        vm.startPrank(users.alice);
        vault.divestSingleXChainSingleVault{ value: value }(divestReq);

        assertEq(vault.totalAssets(), 400 * _1_USDCE + expectedDivestedValue);
        assertEq(vault.totalWithdrawableAssets(), 400 * _1_USDCE);
        assertEq(gateway.totalPendingXChainDivests(), expectedDivestedValue);

        // Simulate vault getting the assets
        bytes32 requestId = gateway.getRequestsQueue()[0];
        deal(USDCE_BASE, gateway.getReceiver(requestId), expectedDivestedValue);
        gateway.settleDivest(requestId, false);

        assertEq(vault.totalAssets(), 400 * _1_USDCE + expectedDivestedValue);
        assertEq(vault.totalWithdrawableAssets(), 400 * _1_USDCE + expectedDivestedValue);
        assertEq(gateway.totalPendingXChainDivests(), 0);
    }

    function test_divestSingleXChainSingleVault_failed() public {
        address vaultAddress = EXACTLY_USDC_VAULT_OPTIMISM;
        uint256 superformId = EXACTLY_USDC_VAULT_ID_OPTIMISM;
        uint64 optimismChainId = 10;

        // Setup cross-chain vault
        oracle.setValues(
            optimismChainId, vaultAddress, _getSharePrice(optimismChainId, vaultAddress), block.timestamp, users.bob
        );
        vault.addVault({
            chainId: optimismChainId,
            superformId: superformId,
            vault: vaultAddress,
            vaultDecimals: _getDecimals(optimismChainId, vaultAddress),
            deductedFees: 0,
            oracle: ISharePriceOracle(address(oracle))
        });

        // Deposit and invest cross-chain
        _depositAtomic(1000 * _1_USDCE, users.alice);
        uint256 investAmount = 600 * _1_USDCE;
        SingleXChainSingleVaultStateReq memory investReq =
            _buildInvestSingleXChainSingleVaultParams(superformId, investAmount);

        investReq.superformData.amount = investAmount;

        uint256 shares = _previewDeposit(optimismChainId, vaultAddress, investAmount);
        vault.investSingleXChainSingleVault{ value: _getInvestSingleXChainSingleVaultValue(superformId, investAmount) }(
            investReq
        );
        _mintSuperpositions(address(gateway.recoveryAddress()), superformId, shares);

        uint256 value = _getDivestSingleXChainSingleVaultValue(superformId, investAmount);

        // Prepare divest request
        SingleXChainSingleVaultStateReq memory divestReq =
            _buildDivestSingleXChainSingleVaultParams(superformId, investAmount);

        VaultReport memory report = oracle.getLatestSharePrice(optimismChainId, vaultAddress);
        uint256 lastSharePrice = report.sharePrice;
        uint256 expectedDivestedValue = lastSharePrice * shares / 10 ** 6;
        divestReq.superformData.outputAmount = expectedDivestedValue;

        // Execute divest
        vm.expectEmit(true, true, true, true);
        emit Divest(expectedDivestedValue);

        vm.startPrank(users.alice);
        vault.divestSingleXChainSingleVault{ value: value }(divestReq);

        assertEq(vault.totalAssets(), 400 * _1_USDCE + expectedDivestedValue);
        assertEq(vault.totalWithdrawableAssets(), 400 * _1_USDCE);
        assertEq(gateway.totalPendingXChainDivests(), expectedDivestedValue);

        // Instead of settling, simulate failure by minting superpositions back
        bytes32 requestId = gateway.getRequestsQueue()[0];
        address receiver = gateway.getReceiver(requestId);
        bytes32 key = ERC20Receiver(receiver).key();
        _mintSuperpositions(receiver, superformId, shares);

        // Verify state after failed divest
        assertEq(config.superPositions.balanceOf(address(vault), superformId), shares);
        (,,,,,, uint128 vaultDebt,) = vault.vaults(superformId);
        assertEq(vaultDebt, expectedDivestedValue);
        assertEq(vault.totalDebt(), vaultDebt);
        assertApproxEq(vault.totalXChainAssets(), 600 * _1_USDCE, 1 * _1_USDCE);
        assertEq(gateway.totalPendingXChainDivests(), 0);
    }

    function test_MetaVault_exitFees_withProfit() public {
        // Initial deposit
        uint256 depositAmount = 1000 * _1_USDCE;
        _depositAtomic(depositAmount, users.alice);

        // Simulate profit by donating to vault
        uint256 profit = 100 * _1_USDCE;
        deal(USDCE_BASE, users.bob, profit);

        vm.startPrank(users.bob);
        USDCE_BASE.safeApprove(address(vault), profit);
        vault.donate(profit);
        vm.stopPrank();

        vm.startPrank(users.alice);

        // Current share price should be higher than initial
        assertGt(vault.sharePrice(), 1e6);

        skip(config.sharesLockTime);

        // Request redeem
        uint256 sharesBalance = vault.balanceOf(users.alice);
        vault.requestRedeem(sharesBalance, users.alice, users.alice);

        // Process redeem request
        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;

        vault.processRedeemRequest(users.alice, sXsV, sXmV, mXsV, mXmV);

        // Calculate expected fees
        uint256 duration = block.timestamp - vault.lastRedeem(users.alice);
        uint256 totalAssets = depositAmount + profit;

        // Calculate hurdle return
        uint256 hurdleReturn = (totalAssets * vault.hurdleRate() * duration) / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 excessReturn = profit > hurdleReturn ? profit - hurdleReturn : 0;

        uint256 expectedPerformanceFees = excessReturn * vault.performanceFee() / vault.MAX_BPS();
        uint256 expectedManagementFees =
            (totalAssets * duration * vault.managementFee()) / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 expectedOracleFees =
            (totalAssets * duration * vault.oracleFee()) / vault.SECS_PER_YEAR() / vault.MAX_BPS();

        uint256 totalExpectedFees = expectedPerformanceFees + expectedManagementFees + expectedOracleFees;
        uint256 totalExpectedFeesShares = vault.convertToShares(totalExpectedFees);

        // Ensure fees don't exceed excess return
        if (totalExpectedFees > excessReturn) {
            totalExpectedFees = excessReturn;
            uint256 totalFeeBps = vault.performanceFee() + vault.managementFee() + vault.oracleFee();
            expectedPerformanceFees = (expectedPerformanceFees * excessReturn) / totalFeeBps;
            expectedManagementFees = (expectedManagementFees * excessReturn) / totalFeeBps;
            expectedOracleFees = (expectedOracleFees * excessReturn) / totalFeeBps;
        }

        // Check fees event emission
        vm.expectEmit(true, true, true, true);
        emit AssessFees(users.alice, expectedManagementFees, expectedPerformanceFees - 1, expectedOracleFees);

        // Redeem
        uint256 receivedAssets = vault.redeem(sharesBalance, users.alice, users.alice);

        // Verify received amount is total minus fees
        assertEq(receivedAssets, totalAssets - totalExpectedFees);

        // Verify fees went to treasury
        assertApproxEq(vault.balanceOf(vault.treasury()), totalExpectedFeesShares, 1);
    }

    function test_MetaVault_chargeGlobalFees() public {
        // Initial deposit
        uint256 depositAmount = 1000 * _1_USDCE;
        _depositAtomic(depositAmount, users.alice);

        // Skip some time to accrue fees
        skip(180 days);

        // Simulate profit by donating to vault
        uint256 profit = 100 * _1_USDCE;
        deal(USDCE_BASE, users.bob, profit);
        vm.startPrank(users.bob);
        USDCE_BASE.safeApprove(address(vault), profit);
        vault.donate(profit);
        vm.stopPrank();

        // Record initial state
        uint256 totalAssets = vault.totalAssets();
        uint256 lastSharePrice = vault.sharePriceWaterMark();
        uint256 duration = block.timestamp - vault.lastFeesCharged();
        uint256 treasurySharesBefore = vault.balanceOf(vault.treasury());

        // Calculate expected fees
        uint256 managementFees =
            totalAssets * duration * vault.managementFee() / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 oracleFees = totalAssets * duration * vault.oracleFee() / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 totalFees = managementFees + oracleFees;

        // Add management fees back to assets for performance fee calculation
        totalAssets += managementFees + oracleFees;

        // Calculate profit after time-based fees
        int256 assetsDelta = int256(totalAssets) - int256(depositAmount);

        uint256 performanceFees;
        if (assetsDelta > 0) {
            uint256 hurdleReturn =
                (depositAmount * vault.hurdleRate() * duration) / vault.SECS_PER_YEAR() / vault.MAX_BPS();
            uint256 totalReturn = uint256(assetsDelta);

            if (vault.sharePrice() > lastSharePrice && totalReturn > hurdleReturn) {
                uint256 excessReturn = totalReturn - hurdleReturn;
                performanceFees = excessReturn * vault.performanceFee() / vault.MAX_BPS();
                totalFees += performanceFees;
            }
        }

        // Charge fees
        vm.startPrank(users.alice);
        vm.expectEmit(true, true, true, true);
        emit AssessFees(address(vault), managementFees, performanceFees, oracleFees);
        uint256 actualFees = vault.chargeGlobalFees();
        vm.stopPrank();

        // Verify results
        assertEq(actualFees, totalFees, "Total fees charged incorrect");
        assertEq(
            vault.balanceOf(vault.treasury()) - treasurySharesBefore,
            vault.convertToShares(totalFees),
            "Treasury shares increase incorrect"
        );
        assertEq(vault.lastFeesCharged(), block.timestamp, "Last fees charged timestamp not updated");
    }

    function test_MetaVault_chargeGlobalFees_BelowWatermark() public {
        MockERC4626 yUsdce = new MockERC4626(USDCE_BASE, "Yearn USDCE", "yUSDCe", true, 0);
        vault.addVault({
            chainId: baseChainId,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            deductedFees: 0,
            oracle: ISharePriceOracle(address(0))
        });

        vault.setManagementFee(100);
        vault.setOracleFee(50);
        // Initial deposit
        uint256 depositAmount = 1000 * _1_USDCE;
        _depositAtomic(depositAmount, users.alice);

        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);
        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);

        // Create large profit to set high watermark
        uint256 initialProfit = 200 * _1_USDCE;
        deal(USDCE_BASE, users.bob, initialProfit);
        vm.startPrank(users.bob);
        USDCE_BASE.safeApprove(address(vault), initialProfit);
        vault.donate(initialProfit);
        vm.stopPrank();

        // Charge fees to set watermark
        vm.prank(users.alice);
        vault.chargeGlobalFees();
        uint256 highWatermark = vault.sharePriceWaterMark();
        vm.stopPrank();

        // Simulate loss and small recovery
        uint256 loss = 250 * _1_USDCE;
        uint256 lostShares = yUsdce.convertToShares(loss);
        vm.startPrank(address(vault));
        address(yUsdce).safeTransfer(users.bob, lostShares);
        vm.stopPrank();

        uint256 recovery = 50 * _1_USDCE;
        deal(USDCE_BASE, users.bob, recovery);
        vm.startPrank(users.bob);
        USDCE_BASE.safeApprove(address(vault), recovery);
        vault.donate(recovery);
        vm.stopPrank();

        skip(180 days);

        // Verify we're below watermark
        assertLt(vault.sharePrice(), highWatermark);

        uint256 totalAssets = vault.totalAssets();
        uint256 duration = block.timestamp - vault.lastFeesCharged();
        uint256 treasurySharesBefore = vault.balanceOf(vault.treasury());

        // Calculate expected fees (only management and oracle, no performance)
        uint256 managementFees =
            totalAssets * duration * vault.managementFee() / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 oracleFees = totalAssets * duration * vault.oracleFee() / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 totalFees = managementFees + oracleFees;

        // Charge fees
        vm.startPrank(users.alice);
        vm.expectEmit(true, true, true, true);
        emit AssessFees(address(vault), managementFees, 0, oracleFees); // No performance fees
        uint256 actualFees = vault.chargeGlobalFees();
        vm.stopPrank();

        // Verify results
        assertEq(actualFees, totalFees, "Total fees charged incorrect");
        assertEq(
            vault.balanceOf(vault.treasury()) - treasurySharesBefore,
            vault.convertToShares(totalFees),
            "Treasury shares increase incorrect"
        );
    }

    function test_MetaVault_chargeGlobalFees_BelowHurdleRate() public {
        // Initial deposit
        uint256 depositAmount = 1000 * _1_USDCE;
        _depositAtomic(depositAmount, users.alice);

        skip(180 days);

        // Simulate small profit below hurdle rate
        uint256 smallProfit = 10 * _1_USDCE; // Very small profit
        deal(USDCE_BASE, users.bob, smallProfit);
        vm.startPrank(users.bob);
        USDCE_BASE.safeApprove(address(vault), smallProfit);
        vault.donate(smallProfit);
        vm.stopPrank();

        uint256 totalAssets = vault.totalAssets();
        uint256 duration = block.timestamp - vault.lastFeesCharged();
        uint256 treasurySharesBefore = vault.balanceOf(vault.treasury());

        // Calculate expected fees
        uint256 managementFees =
            totalAssets * duration * vault.managementFee() / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 oracleFees = totalAssets * duration * vault.oracleFee() / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        totalAssets -= managementFees + oracleFees;

        // Calculate hurdle return
        uint256 hurdleReturn = (depositAmount * vault.hurdleRate() * duration) / vault.SECS_PER_YEAR() / vault.MAX_BPS();

        // Verify profit doesn't exceed hurdle
        assertLe(smallProfit, hurdleReturn, "Profit should be below hurdle rate");

        // Charge fees
        vm.startPrank(users.alice);
        vm.expectEmit(true, true, true, true);
        emit AssessFees(address(vault), managementFees, 0, oracleFees); // No performance fees
        uint256 actualFees = vault.chargeGlobalFees();
        vm.stopPrank();

        // Verify results
        assertEq(actualFees, managementFees + oracleFees, "Total fees charged incorrect");
        assertEq(
            vault.balanceOf(vault.treasury()) - treasurySharesBefore,
            vault.convertToShares(managementFees + oracleFees),
            "Treasury shares increase incorrect"
        );
    }

    function test_MetaVault_chargeGlobalFees_NoProfit() public {
        // Initial deposit
        uint256 depositAmount = 1000 * _1_USDCE;
        _depositAtomic(depositAmount, users.alice);

        skip(180 days);

        uint256 totalAssets = vault.totalAssets();
        uint256 duration = block.timestamp - vault.lastFeesCharged();
        uint256 treasurySharesBefore = vault.balanceOf(vault.treasury());

        // Calculate time-based fees
        uint256 managementFees =
            totalAssets * duration * vault.managementFee() / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 oracleFees = totalAssets * duration * vault.oracleFee() / vault.SECS_PER_YEAR() / vault.MAX_BPS();

        // Charge fees
        vm.startPrank(users.alice);
        vm.expectEmit(true, true, true, true);
        emit AssessFees(address(vault), managementFees, 0, oracleFees);
        uint256 actualFees = vault.chargeGlobalFees();
        vm.stopPrank();

        // Verify results
        assertEq(actualFees, managementFees + oracleFees, "Total fees charged incorrect");
        assertEq(
            vault.balanceOf(vault.treasury()) - treasurySharesBefore,
            vault.convertToShares(managementFees + oracleFees),
            "Treasury shares increase incorrect"
        );
    }

    function test_MetaVault_exitFees_noExcessReturn() public {
        // Initial deposit
        uint256 depositAmount = 1000 * _1_USDCE;
        _depositAtomic(depositAmount, users.alice);

        vault.setOracleFee(0);

        // Simulate small profit that doesn't exceed hurdle
        uint256 profit = 1 * _1_USDCE; // Very small profit
        deal(USDCE_BASE, users.bob, profit);

        vm.startPrank(users.bob);
        USDCE_BASE.safeApprove(address(vault), profit);
        vault.donate(profit);
        vm.stopPrank();

        vm.startPrank(users.alice);

        skip(config.sharesLockTime);

        uint256 sharesBalance = vault.balanceOf(users.alice);
        vault.requestRedeem(sharesBalance, users.alice, users.alice);

        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;
        vault.processRedeemRequest(users.alice, sXsV, sXmV, mXsV, mXmV);

        // Calculate hurdle return
        uint256 duration = block.timestamp - vault.lastRedeem(users.alice);
        uint256 totalAssets = depositAmount + profit;
        uint256 hurdleReturn = (totalAssets * vault.hurdleRate() * duration) / vault.SECS_PER_YEAR() / vault.MAX_BPS();

        // Verify profit doesn't exceed hurdle
        assertLe(profit, hurdleReturn);

        // Redeem - should not charge performance fees
        uint256 receivedAssets = vault.redeem(sharesBalance, users.alice, users.alice);

        // Should receive full amount since profit didn't exceed hurdle
        assertEq(receivedAssets, totalAssets - 1, "1");
        assertEq(USDCE_BASE.balanceOf(vault.treasury()), 0);
    }

    function test_MetaVault_exitFees_belowWatermark_noPerformanceFees() public {
        // Initial deposit
        uint256 depositAmount = 1000 * _1_USDCE;
        _depositAtomic(depositAmount, users.alice);

        // Simulate profit to set watermark
        uint256 initialProfit = 100 * _1_USDCE;
        deal(USDCE_BASE, users.bob, initialProfit);

        vm.startPrank(users.bob);
        USDCE_BASE.safeApprove(address(vault), initialProfit);
        vault.donate(initialProfit);
        vm.stopPrank();

        vm.startPrank(users.alice);

        // Record watermark after initial profit
        uint256 watermark = vault.sharePrice();

        // Simulate loss and then small recovery
        uint256 loss = 150 * _1_USDCE;
        vm.startPrank(address(vault));
        USDCE_BASE.safeTransfer(users.bob, loss);
        MetaVaultWrapper(payable(address(vault))).setTotalIdle(uint128((1000 + 100 - 150) * _1_USDCE));
        vm.stopPrank();

        // Add some profit back, but still below watermark
        uint256 recoveryProfit = 50 * _1_USDCE;
        deal(USDCE_BASE, users.bob, recoveryProfit);

        vm.startPrank(users.bob);
        USDCE_BASE.safeApprove(address(vault), recoveryProfit);
        vault.donate(recoveryProfit);
        vm.stopPrank();

        vm.startPrank(users.alice);

        // Verify we're below watermark
        assertLt(vault.sharePrice(), watermark);

        skip(config.sharesLockTime);

        uint256 sharesBalance = vault.balanceOf(users.alice);
        vault.requestRedeem(sharesBalance, users.alice, users.alice);

        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;
        vault.processRedeemRequest(users.alice, sXsV, sXmV, mXsV, mXmV);

        // Should not charge performance fees when below watermark
        uint256 receivedAssets = vault.redeem(sharesBalance, users.alice, users.alice);

        // Should only charge management and oracle fees if applicable
        uint256 totalAssets = depositAmount + initialProfit - loss + recoveryProfit;
        assertEq(receivedAssets, totalAssets);
        assertEq(USDCE_BASE.balanceOf(vault.treasury()), 0);
    }

    function test_MetaVault_exitFees_feeExemption() public {
        vault.setPerformanceFee(2000);
        vault.setManagementFee(100);
        // Initial deposit
        uint256 depositAmount = 1000 * _1_USDCE;
        _depositAtomic(depositAmount, users.alice);

        // Set fee exemptions for alice
        vm.startPrank(users.bob);
        uint256 performanceFeeExemption = 1000; // 10%
        uint256 managementFeeExemption = 500; // 5%
        uint256 oracleFeeExemption = 200; // 2%
        vm.stopPrank();

        vm.startPrank(users.alice);
        vault.setFeeExcemption(users.alice, managementFeeExemption, performanceFeeExemption, oracleFeeExemption);

        vm.startPrank(users.bob);
        // Simulate significant profit to exceed hurdle
        uint256 profit = 2000 * _1_USDCE;
        deal(USDCE_BASE, users.bob, profit);
        USDCE_BASE.safeApprove(address(vault), profit);
        vault.donate(profit);
        vm.stopPrank();

        vm.startPrank(users.alice);
        skip(config.sharesLockTime);

        uint256 sharesBalance = vault.balanceOf(users.alice);
        vault.requestRedeem(sharesBalance, users.alice, users.alice);

        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;
        vault.processRedeemRequest(users.alice, sXsV, sXmV, mXsV, mXmV);

        // Calculate expected fees with exemptions
        uint256 duration = block.timestamp - vault.lastRedeem(users.alice);
        uint256 totalAssets = depositAmount + profit;

        // Calculate hurdle return
        uint256 hurdleReturn = (totalAssets * vault.hurdleRate() * duration) / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 excessReturn = profit - hurdleReturn;

        uint256 expectedPerformanceFees =
            excessReturn * _sub0(vault.performanceFee(), performanceFeeExemption) / vault.MAX_BPS();
        uint256 expectedManagementFees = (totalAssets * duration * _sub0(vault.managementFee(), managementFeeExemption))
            / vault.SECS_PER_YEAR() / vault.MAX_BPS();
        uint256 expectedOracleFees = (totalAssets * duration * _sub0(vault.oracleFee(), oracleFeeExemption))
            / vault.SECS_PER_YEAR() / vault.MAX_BPS();

        uint256 totalExpectedFees = expectedPerformanceFees + expectedManagementFees + expectedOracleFees;
        uint256 totalExpectedFeesShares = vault.convertToShares(totalExpectedFees);

        // Redeem and verify
        uint256 receivedAssets = vault.redeem(sharesBalance, users.alice, users.alice);
        assertApproxEq(receivedAssets, 1000 * _1_USDCE + profit - totalExpectedFees, 2);
        assertApproxEq(address(vault).balanceOf(vault.treasury()), totalExpectedFeesShares, 2);
    }
}
