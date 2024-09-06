import { Test, console2 } from "forge-std/Test.sol";
import { MaxApyCrossChainVault } from "src/MaxApyCrossChainVault.sol";
import { MockERC20 } from "./helpers/mock/MockERC20.sol";

contract MaxApyCrossChainVaultTest is Test {
    MockERC20 public token;
    MaxApyCrossChainVault public vault;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    function setUp() public {
        token = new MockERC20("kjdsl", "Kjl", 18);
        vault = new MaxApyCrossChainVault(address(token), "jkadflads", "afkdj");

        token.mint(alice, 100_000_000 ether);
        token.mint(bob, 100_000_000 ether);
        token.mint(charlie, 100_000_000 ether);

        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);
        vm.prank(charlie);
        token.approve(address(vault), type(uint256).max);
        vm.startPrank(alice);
    }

    function testRequestDeposit() public {
        uint256 amount = 100 ether;
        vault.requestDeposit(amount, alice, alice);
        assertEq(token.balanceOf(address(vault)), amount);
        assertEq(vault.claimableDepositRequest(alice), 100 ether);
        assertEq(vault.pendingDepositRequest(alice), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
    }

    function testDeposit() public {
        uint256 amount = 100 ether;
        vault.requestDeposit(amount, alice, alice);

        vault.deposit(amount, alice);
        assertEq(token.balanceOf(address(vault)), amount);
        assertEq(vault.claimableDepositRequest(alice), 0);
        assertEq(vault.pendingDepositRequest(alice), 0);
        assertEq(vault.totalAssets(), amount);
        assertGt(vault.balanceOf(alice), 0);
    }

    function testDepositAtomic() public {
        uint256 amount = 100 ether;
        vault.depositAtomic(amount, alice);
        assertEq(token.balanceOf(address(vault)), amount);
        assertEq(vault.claimableDepositRequest(alice), 0);
        assertEq(vault.pendingDepositRequest(alice), 0);
        assertEq(vault.totalAssets(), amount);
        assertGt(vault.balanceOf(alice), 0);
    }
}
