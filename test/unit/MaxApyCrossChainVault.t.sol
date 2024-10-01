import { Test, console2 } from "forge-std/Test.sol";
import { MaxApyCrossChainVault } from "src/MaxApyCrossChainVault.sol";
import { ERC4626 } from "solady/tokens/ERC4626.sol";
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

contract MaxApyCrossChainVaultTest is BaseTest, SuperformActions {
    using SafeTransferLib for address;

    MaxApyCrossChainVault public vault;
    ERC4626 public yUsdce;
    uint64 public constant POLYGON_CHAIN_ID = 137;
    uint24 public sharesLockTime = 30 days;
    uint256 public yUsdceSharePrice;
    MockERC4626Oracle public oracle;
    uint16 managementFee = 2000;
    uint16 oracleFee = 2000;
    uint24 processRedeemSettlement;
    address treasury = makeAddr("treasury");

    function setUp() public override {
        super._setUp("POLYGON", 62495246);
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
            _treasury: treasury
        });

        oracle = new MockERC4626Oracle();
        yUsdceSharePrice = yUsdce.convertToAssets(10 ** yUsdce.decimals());
        vault.addVault({
            chainId: 137,
            superformId: 1,
            vault: address(yUsdce),
            vaultDecimals: yUsdce.decimals(),
            oracle: IERC4626Oracle(address(0))
        });
        vault.grantRoles(users.alice, vault.MANAGER_ROLE());
        vault.grantRoles(users.alice, vault.ORACLE_ROLE());
        vault.grantRoles(users.alice, vault.RELAYER_ROLE());
        USDCE_POLYGON.safeApprove(address(vault), type(uint256).max);
    }

    function test_MaxApyCrossChainVault_initialization() public view {
        assertTrue(vault.isVaultListed(address(yUsdce)));
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

    function test_MaxApyCrossChainVault_investSingleDirectSingleVault() public {
        vault.depositAtomic(1000 * _1_USDCE, users.alice);
        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);

        vm.expectRevert();
        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview + 1);

        uint256 shares = vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);
        assertEq(shares, depositPreview);
        assertEq(vault.totalAssets(), 1000 * _1_USDCE - 1);
        assertEq(vault.totalIdle(), 600 * _1_USDCE);
        assertEq(vault.totalDebt(), 400 * _1_USDCE);
        assertEq(yUsdce.balanceOf(address(vault)), depositPreview);
    }

    function test_MaxApyCrossChainVault_investSingleDirectMultiVault() public {
        ERC4626 yUsdceLender = ERC4626(YEARN_USDCE_LENDER_VAULT_POLYGON);
        vault.addVault({
            chainId: 137,
            superformId: 2,
            vault: address(yUsdceLender),
            vaultDecimals: yUsdceLender.decimals(),
            oracle: IERC4626Oracle(address(0))
        });

        vault.depositAtomic(1000 * _1_USDCE, users.alice);

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

        vm.expectRevert();
        vault.investSingleDirectMultiVault(vaultAddresses, amounts, minAmountsOut);

        minAmountsOut[1] -= 1;

        vault.investSingleDirectMultiVault(vaultAddresses, amounts, minAmountsOut);
        assertEq(vault.totalAssets(), 1000 * _1_USDCE - 2);
        assertEq(vault.totalIdle(), 0 * _1_USDCE);
        assertEq(vault.totalDebt(), 1000 * _1_USDCE);
        assertEq(yUsdce.balanceOf(address(vault)), minAmountsOut[0]);
        assertEq(yUsdceLender.balanceOf(address(vault)), minAmountsOut[1]);
    }

    function test_MaxApyCrossChainVault_investSingleXChainSingleVault() public {
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
        vault.depositAtomic(1000 * _1_USDCE, users.alice);

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

    function test_MaxApyCrossChainVault_processRedeemRequest_from_idle() public {
        uint256 sharesBalance = vault.depositAtomic(1000 * _1_USDCE, users.alice);
        skip(sharesLockTime);
        vault.requestRedeem(vault.balanceOf(users.alice), users.alice, users.alice);
        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;
        vault.processRedeemRequest(users.alice, sXsV, sXmV, mXsV, mXmV);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.claimableRedeemRequest(users.alice), sharesBalance);
        assertEq(vault.pendingRedeemRequest(users.alice), 0);
        uint256 assets = vault.redeem(sharesBalance, users.alice, users.alice);
        assertEq(assets, 1000 * _1_USDCE);
    }

    function test_MaxApyCrossChainVault_processRedeemRequest_from_local_queue() public {
        uint256 sharesBalance = vault.depositAtomic(1000 * _1_USDCE, users.alice);
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
        vault.processRedeemRequest(users.alice, sXsV, sXmV, mXsV, mXmV);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 2);
        assertEq(vault.totalIdle(), 0);
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.claimableRedeemRequest(users.alice), sharesBalance);
        assertEq(vault.pendingRedeemRequest(users.alice), 0);
        uint256 assets = vault.redeem(sharesBalance, users.alice, users.alice);
        assertEq(assets, totalAssetsAfterLock - 2);
    }

    function test_MaxApyCrossChainVault_processRedeemRequest_from_local_and_xchain_queue() public {
        vault.depositAtomic(1000 * _1_USDCE, users.alice);
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

        // skip(sharesLockTime);

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
            vault.processRedeemRequest{ value: _getWithdrawSingleXChainSingleVaultValue(superformId, investAmount) }(
                users.alice, sXsV, sXmV, mXsV, mXmV
            );
        }
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function test_MaxApyCrossChainVault_report() public {
        uint256 sharesBalance = vault.depositAtomic(1000 * _1_USDCE, users.alice);
        skip(vault.SECS_PER_YEAR());
        VaultReport[] memory mockReport = new VaultReport[](0);
        vault.report(mockReport, users.bob);
        assertEq(vault.balanceOf(treasury), 200 * _1_USDCE);
        assertEq(vault.balanceOf(users.bob), 200 * _1_USDCE);
    }
}
