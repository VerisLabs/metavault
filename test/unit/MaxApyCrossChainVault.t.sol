import { Test, console2 } from "forge-std/Test.sol";
import { MaxApyCrossChainVault } from "src/MaxApyCrossChainVault.sol";
import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { MockERC20 } from "../helpers/mock/MockERC20.sol";
import { BaseTest } from "../base/BaseTest.t.sol";
import { _1_USDCE } from "../helpers/Tokens.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IBaseRouter as ISuperformRouter, ISuperformFactory, ISuperPositions } from "src/interfaces/Lib.sol";
import "src/helpers/AddressBook.sol";

contract MaxApyCrossChainVaultTest is BaseTest {
    using SafeTransferLib for address;

    MaxApyCrossChainVault public vault;
    ISuperPositions public superPositions;
    ISuperformRouter public vaultRouter;
    ISuperformFactory public factory;
    ERC4626 public yUsdce;
    uint64 public constant POLYGON_CHAIN_ID = 137;
    uint24 public sharesLockTime = 30 days;
    uint256 yUsdceSharePrice;

    function setUp() public {
        super._setUp("POLYGON", 61_032_901);
        superPositions = ISuperPositions(SUPERFORM_SUPERPOSITIONS_POLYGON);
        vaultRouter = ISuperformRouter(SUPERFORM_ROUTER_POLYGON);
        factory = ISuperformFactory(SUPERFORM_FACTORY_POLYGON);
        yUsdce = ERC4626(YEARN_USDCE_VAULT_POLYGON);
        vault = new MaxApyCrossChainVault(
            USDCE_POLYGON, "maxCrossUSDCE", "maxCrossUSDCE", 2000, sharesLockTime, superPositions, vaultRouter, factory
        );
        yUsdceSharePrice = yUsdce.convertToAssets(10 ** yUsdce.decimals());
        vault.addVault(137, 1, address(yUsdce), yUsdce.decimals(), uint192(yUsdceSharePrice));
        vault.grantRoles(users.alice, vault.MANAGER_ROLE());
        USDCE_POLYGON.safeApprove(address(vault), type(uint256).max);
    }

    function test_MaxApyCrossChainVault_investSingleDirectSingleVault() public {
        vault.depositAtomic(1000 * _1_USDCE, users.alice);
        vault.setAutopilot(true);
        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);

        vm.expectRevert();
        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview + 1);

        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);
        assertEq(vault.totalAssets(), 1000 * _1_USDCE);
        assertEq(vault.totalIdle(), 600 * _1_USDCE);
        assertEq(vault.totalDebt(), 400 * _1_USDCE);
        assertEq(yUsdce.balanceOf(address(vault)), depositPreview);
    }

    function test_MaxApyCrossChainVault_withdraw_from_queue() public {
        vault.depositAtomic(1000 * _1_USDCE, users.alice);
        vault.setAutopilot(true);
        uint256 depositPreview = yUsdce.previewDeposit(400 * _1_USDCE);
        vault.investSingleDirectSingleVault(address(yUsdce), 400 * _1_USDCE, depositPreview);

        skip(sharesLockTime);
        vault.requestRedeem(vault.balanceOf(users.alice), users.alice, users.alice);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 1);
        assertEq(vault.totalIdle(), 0);
    }
}
