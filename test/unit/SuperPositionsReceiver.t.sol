// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { SuperPositionsReceiverWrapper } from "../helpers/mock/SuperPositionsReceiverWrapper.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IERC1155A } from "src/interfaces/IERC1155A.sol";

import { BaseVaultTest } from "../base/BaseVaultTest.t.sol";

import { SuperPositionsReceiverEvents } from "../helpers/SuperPositionsReceiverEvents.sol";
import { DAI_BASE, USDCE_BASE, _1_USDCE } from "../helpers/Tokens.sol";
import { Test, console2 } from "forge-std/Test.sol";

import { IMetaVault, ISuperPositionsReceiver, ISuperformGateway } from "interfaces/Lib.sol";
import { LibString } from "solady/utils/LibString.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { MetaVaultWrapper } from "../helpers/mock/MetaVaultWrapper.sol";
import { MockAllowanceTarget, MockBridgeTarget } from "../helpers/mock/MockBridgeTarget.sol";

import { MetaVault } from "src/MetaVault.sol";

import { SUPERFORM_SUPERPOSITIONS_BASE, USDCE_BASE } from "src/helpers/AddressBook.sol";

import { SuperPositionsReceiver } from "src/crosschain/SuperPositionsReceiver.sol";

contract SuperPositionsReceiverTest is BaseVaultTest, SuperPositionsReceiverEvents {
    using SafeTransferLib for address;
    using LibString for bytes;

    ISuperformGateway public gateway;
    uint32 baseChainId = 137; // polygon
    uint32 destiChainId = 8453; // base

    ISuperPositionsReceiver superPositionsReceiver;

    function _setUpTestEnvironment() private {
        config = baseChainUsdceVaultConfig();
        config.signerRelayer = relayer;
        vault = IMetaVault(address(new MetaVaultWrapper(config)));
        gateway = deployGatewayBase(address(vault), users.alice);
        vault.setGateway(address(gateway));
        gateway.grantRoles(users.alice, gateway.RELAYER_ROLE());

        console2.log("vault address : %s", address(vault));
        console2.log("recovery address : %s", gateway.recoveryAddress());
    }

    function _setupContractLabels() private {
        vm.label(SUPERFORM_SUPERPOSITIONS_BASE, "SuperPositions");
        vm.label(address(vault), "MetaVault");
        vm.label(USDCE_BASE, "USDC");
    }

    function setUp() public {
        super._setUp("BASE", 24_643_414);

        _setUpTestEnvironment();
        _setupContractLabels();

        superPositionsReceiver = ISuperPositionsReceiver(
            address(
                new SuperPositionsReceiverWrapper(
                    baseChainId, address(gateway), address(SUPERFORM_SUPERPOSITIONS_BASE), users.alice
                )
            )
        );

        // Grant roles
        superPositionsReceiver.grantRoles(users.alice, superPositionsReceiver.ADMIN_ROLE());
        superPositionsReceiver.grantRoles(users.alice, superPositionsReceiver.RECOVERY_ROLE());
        vm.stopPrank();
    }

    function test_SetGateway() public {
        address newGateway = makeAddr("newGateway");

        // Should fail if not admin
        vm.expectRevert();
        superPositionsReceiver.setGateway(newGateway);

        // Should succeed if admin
        vm.prank(users.alice);
        superPositionsReceiver.setGateway(newGateway);
        assertEq(superPositionsReceiver.gateway(), newGateway);
    }

    function test_RecoverFunds() public {
        uint256 amount = 1000;

        deal(USDCE_BASE, address(superPositionsReceiver), 100 * _1_USDCE);

        // Should fail if not recovery admin
        vm.prank(users.bob);
        vm.expectRevert();
        superPositionsReceiver.recoverFunds(USDCE_BASE, amount);

        // Should fail on source chain
        vm.chainId(baseChainId);
        vm.prank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("SourceChainRecoveryNotAllowed()"));
        superPositionsReceiver.recoverFunds(USDCE_BASE, amount);

        uint256 before = USDCE_BASE.balanceOf(users.alice);
        // Should succeed on destination chain with recovery admin
        vm.chainId(destiChainId);
        vm.prank(users.alice);
        superPositionsReceiver.recoverFunds(USDCE_BASE, amount);
        assertEq(USDCE_BASE.balanceOf(users.alice) - before, amount);
    }

    function test_SupportsInterface() public {
        assertTrue(superPositionsReceiver.supportsInterface(0x4e2312e0));
        assertFalse(superPositionsReceiver.supportsInterface(0x12345678));
    }

    // Test setMaxBridgeGasLimit function
    function testSetMaxBridgeGasLimit() public {
        uint256 newGasLimit = 3_000_000;

        // Should fail when called by non-admin
        vm.startPrank(users.bob);
        vm.expectRevert();
        superPositionsReceiver.setMaxBridgeGasLimit(newGasLimit);
        vm.stopPrank();

        // Should succeed when called by admin
        vm.startPrank(users.alice);
        superPositionsReceiver.setMaxBridgeGasLimit(newGasLimit);
        vm.stopPrank();

        assertEq(superPositionsReceiver.maxBridgeGasLimit(), newGasLimit);
    }

    function testBridgeToken() public {
        // vm.chainId(deployedChainId);

        bytes memory txData = abi.encodeWithSignature("mockBridgeFunction()");
        address allowanceTarget = makeAddr("allowanceTarget");
        uint256 amount = 10 * _1_USDCE;

        // Deploy mock bridge target
        MockBridgeTarget bridgeTarget = new MockBridgeTarget();
        address payable to = payable(address(bridgeTarget));

        // Should fail when called by non-admin
        vm.startPrank(users.bob);
        vm.expectRevert();
        superPositionsReceiver.bridgeToken(to, txData, address(DAI_BASE), allowanceTarget, amount);
        vm.stopPrank();

        // Should succeed when called by admin
        vm.startPrank(users.alice);
        vm.expectEmit(true, true, true, true);
        emit BridgeInitiated(address(DAI_BASE), amount);
        superPositionsReceiver.bridgeToken(to, txData, address(DAI_BASE), allowanceTarget, amount);
        vm.stopPrank();

        // Verify the token was approved
        assertEq(IERC20(DAI_BASE).allowance(address(superPositionsReceiver), allowanceTarget), amount);
        // Verify bridge target was called
        assertTrue(bridgeTarget.wasCalled());
    }
}
