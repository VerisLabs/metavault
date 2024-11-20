// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { MaxApyCrossChainVault } from "../../src/MaxApyCrossChainVault.sol";
import { SharePriceOracle } from "../../src/crosschain/SharePriceOracle.sol";

import { IBaseRouter } from "../../src/interfaces/IBaseRouter.sol";
import { ISuperPositions } from "../../src/interfaces/ISuperPositions.sol";
import { ISuperformFactory } from "../../src/interfaces/ISuperformFactory.sol";
import { MsgCodec } from "../../src/lib/MsgCodec.sol";
import { VaultConfig } from "../../src/types/Lib.sol";
import { MockERC20 } from "../helpers/mock/MockERC20.sol";
import { Test } from "forge-std/Test.sol";

import { ERC1155 } from "solady/tokens/ERC1155.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";

contract SharePriceOracleTest is Test {
    SharePriceOracle public oracle;
    address public admin;
    address public endpoint;
    uint32 public constant CHAIN_ID = 1;
    MaxApyCrossChainVault public vault1;
    MaxApyCrossChainVault public vault2;
    MockERC20 public underlyingAsset;

    ISuperPositions public mockSuperPositions;
    IBaseRouter public mockVaultRouter;
    ISuperformFactory public mockFactory;

    event SharePricesUpdated(uint32 indexed srcChainId, address[] vaults, uint256[] prices);

    event RoleGranted(address indexed account, uint256 indexed role);
    event RoleRevoked(address indexed account, uint256 indexed role);

    event LzEndpointUpdated(address indexed oldEndpoint, address indexed newEndpoint);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        admin = address(this);
        endpoint = address(0xE4626);

        oracle = new SharePriceOracle(CHAIN_ID, admin);

        underlyingAsset = new MockERC20("Test Token", "TEST", 18);

        mockSuperPositions = ISuperPositions(makeAddr("mockSuperPositions"));
        mockVaultRouter = IBaseRouter(makeAddr("mockVaultRouter"));
        mockFactory = ISuperformFactory(makeAddr("mockFactory"));

        VaultConfig memory config1 = VaultConfig({
            asset: address(underlyingAsset),
            name: "Vault A",
            symbol: "VLTA",
            factory: mockFactory,
            superPositions: mockSuperPositions,
            vaultRouter: mockVaultRouter,
            treasury: makeAddr("treasury"),
            managementFee: 100, // 1%
            performanceFee: 1000, // 10%
            oracleFee: 50, // 0.5%
            recoveryAddress: makeAddr("recovery"),
            sharesLockTime: 1 days,
            processRedeemSettlement: 1 days,
            assetHurdleRate: 500, // 5%
            signerRelayer: makeAddr("relayer")
        });

        VaultConfig memory config2 = VaultConfig({
            asset: address(underlyingAsset),
            name: "Vault B",
            symbol: "VLTB",
            factory: mockFactory,
            superPositions: mockSuperPositions,
            vaultRouter: mockVaultRouter,
            treasury: makeAddr("treasury"),
            managementFee: 100,
            performanceFee: 1000,
            oracleFee: 50,
            recoveryAddress: makeAddr("recovery"),
            sharesLockTime: 1 days,
            processRedeemSettlement: 1 days,
            assetHurdleRate: 500,
            signerRelayer: makeAddr("relayer")
        });

        vm.mockCall(
            address(mockSuperPositions), abi.encodeWithSelector(ERC1155.setApprovalForAll.selector), abi.encode(true)
        );

        vm.mockCall(
            address(mockVaultRouter),
            abi.encodeWithSelector(IBaseRouter.singleXChainSingleVaultDeposit.selector),
            abi.encode()
        );

        vm.mockCall(
            address(mockFactory), abi.encodeWithSelector(ISuperformFactory.isSuperform.selector), abi.encode(true)
        );

        vault1 = new MaxApyCrossChainVault(config1);
        vault2 = new MaxApyCrossChainVault(config2);

        underlyingAsset.mint(address(vault1), 1000e18);
        underlyingAsset.mint(address(vault2), 1000e18);

        vm.prank(admin);
        oracle.setLzEndpoint(endpoint);
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testConstructor() public {
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(address(0), address(this));
        SharePriceOracle newOracle = new SharePriceOracle(CHAIN_ID, address(this));

        assertEq(newOracle.chainId(), CHAIN_ID);
        assertTrue(newOracle.hasRole(address(this), newOracle.ADMIN_ROLE()));
    }

    function testConstructorInvalidAdmin() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidAdminAddress()"));
        new SharePriceOracle(CHAIN_ID, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        ENDPOINT MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetLzEndpoint() public {
        address newEndpoint = makeAddr("newEndpoint");

        vm.startPrank(admin);

        vm.expectEmit(true, true, false, true);
        emit LzEndpointUpdated(endpoint, newEndpoint);
        vm.expectEmit(true, true, false, true);
        emit RoleGranted(newEndpoint, oracle.ENDPOINT_ROLE());

        oracle.setLzEndpoint(newEndpoint);
        assertTrue(oracle.hasRole(newEndpoint, oracle.ENDPOINT_ROLE()));

        vm.stopPrank();
    }

    function testSetLzEndpointZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        oracle.setLzEndpoint(address(0));
    }

    function testSetLzEndpointUnauthorized() public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert();
        oracle.setLzEndpoint(makeAddr("newEndpoint"));
    }

    /*//////////////////////////////////////////////////////////////
                        ROLE MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testRoleManagement() public {
        address newEndpoint = makeAddr("newEndpoint");

        vm.startPrank(admin);

        vm.expectEmit(true, true, false, true);
        emit RoleGranted(newEndpoint, oracle.ENDPOINT_ROLE());
        oracle.grantRole(newEndpoint, oracle.ENDPOINT_ROLE());
        assertTrue(oracle.hasRole(newEndpoint, oracle.ENDPOINT_ROLE()));

        vm.expectEmit(true, true, false, true);
        emit RoleRevoked(newEndpoint, oracle.ENDPOINT_ROLE());
        oracle.revokeRole(newEndpoint, oracle.ENDPOINT_ROLE());
        assertFalse(oracle.hasRole(newEndpoint, oracle.ENDPOINT_ROLE()));

        vm.stopPrank();
    }

    function testGrantInvalidRole() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("InvalidRole()"));
        oracle.grantRole(endpoint, 0);
    }

    function testRevokeRoleZeroAddress() public {
        vm.startPrank(admin);

        uint256 roleToRevoke = oracle.ENDPOINT_ROLE();

        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        oracle.revokeRole(address(0), roleToRevoke);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        SHARE PRICE TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetSharePrices() public {
        address[] memory vaults = new address[](2);
        vaults[0] = address(vault1);
        vaults[1] = address(vault2);

        MsgCodec.VaultReport[] memory reports = oracle.getSharePrices(vaults);

        assertEq(reports.length, 2);
        assertEq(reports[0].vaultAddress, address(vault1));
        assertEq(reports[0].sharePrice, 1e18);
        assertEq(reports[0].chainId, CHAIN_ID);
        assertEq(reports[1].vaultAddress, address(vault2));
        assertEq(reports[1].sharePrice, 1e18);
        assertEq(reports[1].chainId, CHAIN_ID);
    }

    function testUpdateSharePrices() public {
        uint32 srcChainId = 2;
        MsgCodec.VaultReport[] memory reports = new MsgCodec.VaultReport[](2);
        reports[0] = MsgCodec.VaultReport({
            lastUpdate: uint64(block.timestamp),
            chainId: srcChainId,
            vaultAddress: address(vault1),
            sharePrice: 1.2e18
        });
        reports[1] = MsgCodec.VaultReport({
            lastUpdate: uint64(block.timestamp),
            chainId: srcChainId,
            vaultAddress: address(vault2),
            sharePrice: 1.3e18
        });

        address[] memory expectedVaults = new address[](2);
        expectedVaults[0] = address(vault1);
        expectedVaults[1] = address(vault2);

        uint256[] memory expectedPrices = new uint256[](2);
        expectedPrices[0] = 1.2e18;
        expectedPrices[1] = 1.3e18;

        vm.expectEmit(true, true, false, true);
        emit SharePricesUpdated(srcChainId, expectedVaults, expectedPrices);

        vm.prank(endpoint);
        oracle.updateSharePrices(srcChainId, reports);

        {
            (uint64 lastUpdate1, uint32 chainId1, address addr1, uint256 price1) =
                oracle.sharePrices(srcChainId, address(vault1));
            assertEq(chainId1, srcChainId);
            assertEq(addr1, address(vault1));
            assertEq(price1, 1.2e18);
            assertGt(lastUpdate1, 0);
        }

        {
            (uint64 lastUpdate2, uint32 chainId2, address addr2, uint256 price2) =
                oracle.sharePrices(srcChainId, address(vault2));
            assertEq(chainId2, srcChainId);
            assertEq(addr2, address(vault2));
            assertEq(price2, 1.3e18);
            assertGt(lastUpdate2, 0);
        }
    }

    function testGetStoredSharePrices() public {
        uint32 srcChainId = 2;
        MsgCodec.VaultReport[] memory reports = new MsgCodec.VaultReport[](2);
        reports[0] = MsgCodec.VaultReport({
            lastUpdate: uint64(block.timestamp),
            chainId: srcChainId,
            vaultAddress: address(vault1),
            sharePrice: 1.2e18
        });
        reports[1] = MsgCodec.VaultReport({
            lastUpdate: uint64(block.timestamp),
            chainId: srcChainId,
            vaultAddress: address(vault2),
            sharePrice: 1.3e18
        });

        vm.prank(endpoint);
        oracle.updateSharePrices(srcChainId, reports);

        address[] memory vaultAddresses = new address[](2);
        vaultAddresses[0] = address(vault1);
        vaultAddresses[1] = address(vault2);

        MsgCodec.VaultReport[] memory storedReports = oracle.getStoredSharePrices(srcChainId, vaultAddresses);

        assertEq(storedReports.length, 2);
        assertEq(storedReports[0].sharePrice, 1.2e18);
        assertEq(storedReports[1].sharePrice, 1.3e18);
    }

    function testUnauthorizedUpdateSharePrices() public {
        MsgCodec.VaultReport[] memory reports = new MsgCodec.VaultReport[](1);
        reports[0] = MsgCodec.VaultReport({
            lastUpdate: uint64(block.timestamp),
            chainId: 2,
            vaultAddress: address(vault1),
            sharePrice: 1.2e18
        });

        vm.prank(address(0x1234));
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        oracle.updateSharePrices(2, reports);
    }

    function testFuzzUpdateSharePrices(uint32 srcChainId, uint256 sharePrice) public {
        vm.assume(sharePrice > 0 && sharePrice < type(uint256).max);

        MsgCodec.VaultReport[] memory reports = new MsgCodec.VaultReport[](1);
        reports[0] = MsgCodec.VaultReport({
            lastUpdate: uint64(block.timestamp),
            chainId: srcChainId,
            vaultAddress: address(vault1),
            sharePrice: sharePrice
        });

        vm.prank(endpoint);
        oracle.updateSharePrices(srcChainId, reports);

        (,,, uint256 storedSharePrice) = oracle.sharePrices(srcChainId, address(vault1));
        assertEq(sharePrice, storedSharePrice);
    }

    function testGetRoles() public {
        assertEq(oracle.getRoles(admin), oracle.ADMIN_ROLE());

        assertEq(oracle.getRoles(endpoint), oracle.ENDPOINT_ROLE());

        assertEq(oracle.getRoles(address(0x123)), 0);
    }

    function testFullGrantRoleFlow() public {
        address testAccount = makeAddr("testAccount");

        vm.startPrank(admin);

        oracle.grantRole(testAccount, oracle.ENDPOINT_ROLE());

        assertEq(oracle.getRoles(testAccount), oracle.ENDPOINT_ROLE());

        oracle.revokeRole(testAccount, oracle.ENDPOINT_ROLE());

        assertEq(oracle.getRoles(testAccount), 0);

        vm.stopPrank();
    }

    function testInvalidRoleRevoke() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSignature("InvalidRole()"));
        oracle.revokeRole(makeAddr("testAccount"), 0);
        vm.stopPrank();
    }

    function testGetSharePricesEmpty() public {
        address[] memory emptyVaults = new address[](0);
        MsgCodec.VaultReport[] memory reports = oracle.getSharePrices(emptyVaults);
        assertEq(reports.length, 0);
    }

    function testGetStoredSharePricesEmpty() public {
        address[] memory emptyVaults = new address[](0);
        MsgCodec.VaultReport[] memory reports = oracle.getStoredSharePrices(2, emptyVaults);
        assertEq(reports.length, 0);
    }

    function testFuzz_UpdateSharePricesBatch(uint32 srcChainId, uint256[] calldata sharePrices) public {
        vm.assume(sharePrices.length > 0 && sharePrices.length <= 10);

        MsgCodec.VaultReport[] memory reports = new MsgCodec.VaultReport[](sharePrices.length);
        address[] memory vaults = new address[](sharePrices.length);
        uint256[] memory expectedPrices = new uint256[](sharePrices.length);

        for (uint256 i = 0; i < sharePrices.length; i++) {
            vm.assume(sharePrices[i] > 0 && sharePrices[i] < type(uint256).max);
            address mockVault = address(uint160(i + 1));
            reports[i] = MsgCodec.VaultReport({
                lastUpdate: uint64(block.timestamp),
                chainId: srcChainId,
                vaultAddress: mockVault,
                sharePrice: sharePrices[i]
            });
            vaults[i] = mockVault;
            expectedPrices[i] = sharePrices[i];
        }

        vm.expectEmit(true, true, false, true);
        emit SharePricesUpdated(srcChainId, vaults, expectedPrices);

        vm.prank(endpoint);
        oracle.updateSharePrices(srcChainId, reports);

        for (uint256 i = 0; i < vaults.length; i++) {
            (uint64 lastUpdate, uint32 chainId, address addr, uint256 price) = oracle.sharePrices(srcChainId, vaults[i]);

            assertEq(chainId, srcChainId);
            assertEq(addr, vaults[i]);
            assertEq(price, sharePrices[i]);
            assertEq(lastUpdate, block.timestamp);
        }
    }

    function testFuzz_RoleManagementSimple(address account, uint256 role) public {
        vm.assume(account != address(0));
        vm.assume(role > 2 && role < type(uint256).max / 4);
        vm.assume(role != oracle.ADMIN_ROLE() && role != oracle.ENDPOINT_ROLE());

        vm.startPrank(admin);

        oracle.grantRole(account, role);
        assertTrue(oracle.hasRole(account, role), "Role not granted");

        oracle.revokeRole(account, role);
        assertFalse(oracle.hasRole(account, role), "Role not revoked");

        vm.stopPrank();
    }

    function testFuzz_GetSharePricesSimple(uint256 initialBalance, uint256 sharePrice) public {
        initialBalance = bound(initialBalance, 1e18, 1000e18);
        sharePrice = bound(sharePrice, 1e18, 100e18);

        VaultConfig memory config = VaultConfig({
            asset: address(underlyingAsset),
            name: "Test Vault",
            symbol: "TVLT",
            factory: mockFactory,
            superPositions: mockSuperPositions,
            vaultRouter: mockVaultRouter,
            treasury: makeAddr("treasury"),
            managementFee: 100,
            performanceFee: 1000,
            oracleFee: 50,
            recoveryAddress: makeAddr("recovery"),
            sharesLockTime: 1 days,
            processRedeemSettlement: 1 days,
            assetHurdleRate: 500,
            signerRelayer: makeAddr("relayer")
        });

        vm.mockCall(
            address(mockSuperPositions), abi.encodeWithSelector(ERC1155.setApprovalForAll.selector), abi.encode(true)
        );

        vm.mockCall(
            address(mockVaultRouter),
            abi.encodeWithSelector(IBaseRouter.singleXChainSingleVaultDeposit.selector),
            abi.encode()
        );

        vm.mockCall(
            address(mockFactory), abi.encodeWithSelector(ISuperformFactory.isSuperform.selector), abi.encode(true)
        );

        vm.mockCall(address(underlyingAsset), abi.encodeWithSelector(ERC20.approve.selector), abi.encode(true));

        MaxApyCrossChainVault testVault = new MaxApyCrossChainVault(config);
        underlyingAsset.mint(address(testVault), initialBalance);

        address[] memory vaults = new address[](1);
        vaults[0] = address(testVault);

        MsgCodec.VaultReport[] memory updateReports = new MsgCodec.VaultReport[](1);
        updateReports[0] = MsgCodec.VaultReport({
            lastUpdate: uint64(block.timestamp),
            chainId: CHAIN_ID,
            vaultAddress: address(testVault),
            sharePrice: sharePrice
        });

        vm.prank(endpoint);
        oracle.updateSharePrices(CHAIN_ID, updateReports);

        MsgCodec.VaultReport[] memory storedReports = oracle.getStoredSharePrices(CHAIN_ID, vaults);
        assertEq(storedReports[0].sharePrice, sharePrice, "Share price mismatch");
        assertEq(storedReports[0].vaultAddress, address(testVault), "Vault address mismatch");
        assertEq(storedReports[0].chainId, CHAIN_ID, "Chain ID mismatch");
    }

    function testFuzz_EndpointManagement(address newEndpoint, uint256 role) public {
        vm.assume(newEndpoint != address(0));
        vm.assume(newEndpoint != endpoint);
        vm.assume(role > oracle.ENDPOINT_ROLE());

        vm.startPrank(admin);

        // Test endpoint update
        vm.expectEmit(true, true, false, true);
        emit LzEndpointUpdated(endpoint, newEndpoint);

        oracle.setLzEndpoint(newEndpoint);
        assertTrue(oracle.hasRole(newEndpoint, oracle.ENDPOINT_ROLE()));

        // Test additional role grant to endpoint
        oracle.grantRole(newEndpoint, role);
        assertTrue(oracle.hasRole(newEndpoint, role));
        assertTrue(oracle.hasRole(newEndpoint, oracle.ENDPOINT_ROLE()));

        vm.stopPrank();
    }
}
