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
    ERC4626 public maxUsdce;
    uint64 public constant POLYGON_CHAIN_ID = 137;
    uint24 public sharesLockTime = 30 days;

    function setUp() public {
        super._setUp("POLYGON", 61_032_901);
        superPositions = ISuperPositions(SUPERFORM_SUPERPOSITIONS_POLYGON);
        vaultRouter = ISuperformRouter(SUPERFORM_ROUTER_POLYGON);
        factory = ISuperformFactory(SUPERFORM_FACTORY_POLYGON);
        maxUsdce = ERC4626(MAXAPY_USDCE_VAULT_POLYGON);
        vault = new MaxApyCrossChainVault(
            USDCE_POLYGON, "maxCrossUSDCE", "maxCrossUSDCE", 2000, sharesLockTime, superPositions, vaultRouter, factory
        );

        (uint256 superformId,) = factory.createSuperform(1, address(maxUsdce));
        vault.addVault(137, superformId, address(maxUsdce), 12, uint192(_1_USDCE));
        USDCE_POLYGON.safeApprove(address(vault), type(uint256).max);
    }

    function test_MaxApyCrossChainVault_invest() public { }
}
