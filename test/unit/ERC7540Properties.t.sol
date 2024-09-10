import { Test, console2 } from "forge-std/Test.sol";
import { MaxApyCrossChainVault } from "src/MaxApyCrossChainVault.sol";
import { MockERC20 } from "../helpers/mock/MockERC20.sol";
import { BaseTest } from "../base/BaseTest.t.sol";
import { _1_USDCE } from "../helpers/Tokens.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IBaseRouter as ISuperformRouter, ISuperformFactory, ISuperPositions } from "src/interfaces/Lib.sol";
import "src/helpers/AddressBook.sol";

contract ERC7540PropertiesTest is BaseTest {
    using SafeTransferLib for address;

    MaxApyCrossChainVault public vault;
    ISuperPositions superPositions;
    ISuperformRouter vaultRouter;
    ISuperformFactory factory;
    uint24 sharesLockTime = 30 days;

    function setUp() public {
        super._setUp("POLYGON", 61_032_901);
        superPositions = ISuperPositions(SUPERFORM_SUPERPOSITIONS_POLYGON);
        vaultRouter = ISuperformRouter(SUPERFORM_ROUTER_POLYGON);
        factory = ISuperformFactory(SUPERFORM_FACTORY_POLYGON);
        vault = new MaxApyCrossChainVault(
            USDCE_POLYGON, "maxCrossUSDCE", "maxCrossUSDCE", 2000, sharesLockTime, superPositions, vaultRouter, factory
        );
        USDCE_POLYGON.safeApprove(address(vault), type(uint256).max);
    }

    function test_erc7540_requestDeposit() public {
        uint256 amount = 100 * _1_USDCE;
        vault.requestDeposit(amount, users.alice, users.alice);
        assertEq(USDCE_POLYGON.balanceOf(address(vault)), amount);
        assertEq(vault.claimableDepositRequest(users.alice), 100 * _1_USDCE);
        assertEq(vault.pendingDepositRequest(users.alice), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(users.alice), 0);
    }

    function test_erc7540_deposit() public {
        uint256 amount = 100 * _1_USDCE;
        vault.requestDeposit(amount, users.alice, users.alice);

        uint256 shares = vault.deposit(amount, users.alice);
        assertEq(USDCE_POLYGON.balanceOf(address(vault)), amount);
        assertEq(vault.claimableDepositRequest(users.alice), 0);
        assertEq(vault.pendingDepositRequest(users.alice), 0);
        assertEq(vault.totalAssets(), amount);
        assertEq(shares, amount);
        assertEq(vault.balanceOf(users.alice), shares);
    }

    function test_erc7540_mint() public {
        uint256 amount = 100 * _1_USDCE;
        vault.requestDeposit(amount, users.alice, users.alice);

        uint256 assets = vault.mint(amount, users.alice);
        assertEq(USDCE_POLYGON.balanceOf(address(vault)), amount);
        assertEq(vault.claimableDepositRequest(users.alice), 0);
        assertEq(vault.pendingDepositRequest(users.alice), 0);
        assertEq(vault.totalAssets(), amount);
        assertEq(assets, amount);
        assertEq(vault.balanceOf(users.alice), assets);
    }

    function test_erc7540_depositAtomic() public {
        uint256 amount = 100 * _1_USDCE;
        uint256 shares = vault.depositAtomic(amount, users.alice);
        assertEq(USDCE_POLYGON.balanceOf(address(vault)), amount);
        assertEq(vault.claimableDepositRequest(users.alice), 0);
        assertEq(vault.pendingDepositRequest(users.alice), 0);
        assertEq(vault.totalAssets(), amount);
        assertEq(shares, amount);
        assertEq(vault.balanceOf(users.alice), shares);
    }

    function test_erc7540_mintAtomic() public {
        uint256 amount = 100 * _1_USDCE;
        uint256 assets = vault.mintAtomic(amount, users.alice);
        assertEq(USDCE_POLYGON.balanceOf(address(vault)), amount);
        assertEq(vault.claimableDepositRequest(users.alice), 0);
        assertEq(vault.pendingDepositRequest(users.alice), 0);
        assertEq(vault.totalAssets(), amount);
        assertEq(assets, amount);
        assertEq(vault.balanceOf(users.alice), assets);
    }

    function test_erc7540_requestRedeem_sharesLocked() public {
        uint256 amount = 100 * _1_USDCE;
        vault.requestDeposit(amount, users.alice, users.alice);
        uint256 shares = vault.deposit(amount, users.alice);
        vm.expectRevert();
        vault.requestRedeem(shares, users.alice, users.alice);
    }

    function test_erc7540_requestRedeem() public {
        uint256 amount = 100 * _1_USDCE;
        vault.requestDeposit(amount, users.alice, users.alice);
        uint256 shares = vault.deposit(amount, users.alice);
        skip(sharesLockTime);

        uint256 snapshotId = vm.snapshot();
        vault.requestRedeem(shares, users.alice, users.alice);
        assertEq(vault.pendingRedeemRequest(users.alice), shares);
        assertEq(vault.claimableRedeemRequest(users.alice), 0);
        assertEq(vault.totalSupply(), amount);
        assertEq(vault.totalAssets(), amount);
        vm.revertTo(snapshotId);
        vault.setAutopilot(true);
        vault.requestRedeem(shares, users.alice, users.alice);
        assertEq(vault.pendingRedeemRequest(users.alice), 0);
        assertEq(vault.claimableRedeemRequest(users.alice), amount);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
    }

    function test_erc7540_redeem() public {
        uint256 amount = 100 * _1_USDCE;
        vault.requestDeposit(amount, users.alice, users.alice);
        uint256 shares = vault.deposit(amount, users.alice);
        skip(sharesLockTime);
        vault.setAutopilot(true);
        vault.requestRedeem(shares, users.alice, users.alice);
        uint256 balanceBefore = USDCE_POLYGON.balanceOf(users.alice);
        uint256 assets = vault.redeem(shares, users.alice, users.alice);
        uint256 balanceAfter = USDCE_POLYGON.balanceOf(users.alice);
        assertEq(assets, amount);
        assertEq(balanceAfter - balanceBefore, amount);
        assertEq(vault.pendingRedeemRequest(users.alice), 0);
        assertEq(vault.claimableRedeemRequest(users.alice), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
    }

    function test_erc7540_withdraw() public {
        uint256 amount = 100 * _1_USDCE;
        vault.requestDeposit(amount, users.alice, users.alice);
        uint256 shares = vault.deposit(amount, users.alice);
        skip(sharesLockTime);
        vault.setAutopilot(true);
        vault.requestRedeem(shares, users.alice, users.alice);
        uint256 balanceBefore = USDCE_POLYGON.balanceOf(users.alice);
        uint256 burntShares = vault.withdraw(amount, users.alice, users.alice);
        uint256 balanceAfter = USDCE_POLYGON.balanceOf(users.alice);
        assertEq(burntShares, shares);
        assertEq(balanceAfter - balanceBefore, amount);
        assertEq(vault.pendingRedeemRequest(users.alice), 0);
        assertEq(vault.claimableRedeemRequest(users.alice), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
    }
}
