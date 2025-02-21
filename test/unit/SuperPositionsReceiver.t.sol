// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { SuperPositionsReceiverWrapper } from "../helpers/mock/SuperPositionsReceiverWrapper.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IERC1155A } from "src/interfaces/IERC1155A.sol";

import { BaseVaultTest } from "../base/BaseVaultTest.t.sol";

import { SuperPositionsReceiverEvents } from "../helpers/SuperPositionsReceiverEvents.sol";
import { _1_USDCE, USDCE_BASE } from "../helpers/Tokens.sol";
import { Test, console2 } from "forge-std/Test.sol";

import { IMetaVault, ISuperformGateway, ISuperPositionsReceiver } from "interfaces/Lib.sol";
import { LibString } from "solady/utils/LibString.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { MetaVaultWrapper } from "../helpers/mock/MetaVaultWrapper.sol";

import { MetaVault } from "src/MetaVault.sol";

import {
    SUPERFORM_SUPERPOSITIONS_BASE,
    USDCE_BASE
} from "src/helpers/AddressBook.sol";

import {SuperPositionsReceiver} from "src/crosschain/SuperPositionsReceiver.sol";


contract SuperPositionsReceiverTest is BaseVaultTest, SuperPositionsReceiverEvents {
    using SafeTransferLib for address;
    using LibString for bytes;

    ISuperformGateway public gateway;
    uint32 baseChainId = 137;       // polygon
    uint32 destiChainId = 8453;     // base

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

        superPositionsReceiver = ISuperPositionsReceiver(address(new SuperPositionsReceiverWrapper(
            baseChainId,
            address(gateway),
            address(SUPERFORM_SUPERPOSITIONS_BASE),
            users.alice
        )));
        
        // Grant roles
        superPositionsReceiver.grantRoles(users.alice, superPositionsReceiver.ADMIN_ROLE());
        superPositionsReceiver.grantRoles(users.alice, superPositionsReceiver.RECOVERY_ROLE());
        superPositionsReceiver.setBackendSigner(users.alice);
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
    
    function test_SetBackendSigner() public {
        address newSigner = makeAddr("newSigner");
        
        // Should fail if not owner
        vm.prank(users.bob);
        vm.expectRevert();
        superPositionsReceiver.setBackendSigner(newSigner);
        
        // Should fail if zero address
        console2.log("### ~ test_SetBackendSigner ~ address(0));:", address(0));
        vm.prank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        superPositionsReceiver.setBackendSigner(address(0));
        
        // Should succeed if owner
        vm.prank(users.alice);
        superPositionsReceiver.setBackendSigner(newSigner);
        assertEq(superPositionsReceiver.backendSigner(), newSigner);
    }

    function test_RecoverFunds() public {
        uint256 amount = 1000;

        deal(USDCE_BASE, address(superPositionsReceiver), 100 * _1_USDCE);
        
        // // Change chain ID to destination chain
        // vm.chainId(DEST_CHAIN);
        
        // Should fail if not recovery admin
        vm.prank(users.bob);
        vm.expectRevert();
        superPositionsReceiver.recoverFunds(USDCE_BASE, amount);
        
        // Should fail on source chain
        vm.chainId(baseChainId);
        vm.prank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("SourceChainRecoveryNotAllowed()"));
        superPositionsReceiver.recoverFunds(USDCE_BASE, amount);
        
        // Should succeed on destination chain with recovery admin
        vm.chainId(destiChainId);
        vm.prank(users.alice);
        superPositionsReceiver.recoverFunds(USDCE_BASE, amount);
        assertEq(USDCE_BASE.balanceOf(users.alice), amount);
    }
    
    function test_SignatureVerification() public {

        (, uint256 alicePk) = makeAddrAndKey("alice");

        bytes32 messageHash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, messageHash);

        address signer = ecrecover(messageHash, v, r, s);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Set the backend signer
        vm.prank(users.alice);
        superPositionsReceiver.setBackendSigner(signer);
        
        // Test valid signature
        bytes4 result = superPositionsReceiver.isValidSignature(messageHash, signature);
        assertEq(result, superPositionsReceiver.MAGIC_VALUE());
        
        // Test invalid signature
        (, uint256 bobPk) = makeAddrAndKey("bob");

        messageHash = keccak256("test message");
        (v, r, s) = vm.sign(bobPk, messageHash);

        signer = ecrecover(messageHash, v, r, s);
        bytes memory signatureBob = abi.encodePacked(r, s, v);

        
        console2.log("### ~ test_SignatureVerification ~ invalidSignature:");
        result = superPositionsReceiver.isValidSignature(messageHash, signatureBob);
        assertEq(result, superPositionsReceiver.INVALID_SIGNATURE());
    }
    
    function test_ApproveToken() public {
        uint256 amount = 100 * _1_USDCE;
        address spender = makeAddr("spender");
        
        // Should fail if not owner
        vm.prank(users.bob);
        vm.expectRevert();
        superPositionsReceiver.approveToken(USDCE_BASE, spender, amount);
        
        // Should fail for zero addresses
        vm.startPrank(users.alice);
        vm.expectRevert(SuperPositionsReceiver.ZeroAddress.selector);
        superPositionsReceiver.approveToken(address(0), spender, amount);
        
        vm.expectRevert(SuperPositionsReceiver.ZeroAddress.selector);
        superPositionsReceiver.approveToken(USDCE_BASE, address(0), amount);
        vm.stopPrank();
        
        // Should succeed with valid parameters
        vm.expectEmit();
        emit TokenApproval(USDCE_BASE, spender, amount);
        
        vm.prank(users.alice);
        superPositionsReceiver.approveToken(USDCE_BASE, spender, amount);
        
        assertEq(IERC20(USDCE_BASE).allowance(address(superPositionsReceiver), spender), amount);
    }
    
    // function test_OnERC1155Received() public {
    //     uint256 superformId = 1;
    //     uint256 value = 1;
        
    //     IERC1155A(SUPERFORM_SUPERPOSITIONS_BASE).mintSingle(address(superPositionsReceiver), superformId, value);
        
    //     // Mint or deal tokens to the receiver first
    //     // Since it's trying to transfer tokens, we need to ensure it has them
    //     vm.startPrank(address(SUPERFORM_SUPERPOSITIONS_BASE));
        
    //     // vm.stopPrank();
        
    //     // Should succeed on source chain with valid parameters
    //     vm.chainId(baseChainId);
    //     vm.startPrank(address(SUPERFORM_SUPERPOSITIONS_BASE));
    //     bytes4 result = superPositionsReceiver.onERC1155Received(
    //         address(0),
    //         address(0),
    //         superformId,
    //         value,
    //         ""
    //     );
    //     assertEq(result, superPositionsReceiver.onERC1155Received.selector);
    //     vm.stopPrank();
        
    //     // Should revert on source chain with invalid sender
    //     vm.expectRevert();
    //     superPositionsReceiver.onERC1155Received(
    //         address(0),
    //         address(0),
    //         superformId,
    //         value,
    //         ""
    //     );
    // }
    
    function test_SupportsInterface() public {
        assertTrue(superPositionsReceiver.supportsInterface(0x4e2312e0));
        assertFalse(superPositionsReceiver.supportsInterface(0x12345678));
    }
        

}