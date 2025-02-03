// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { SetUp } from "./helpers/SetUp.t.sol";

contract MetaVaultInvariants is SetUp {
    function setUp() public {
        _setUpToken();
        _setUpVault();
    }

    function invariantMetaVault__SharePreviews() public view {
        vaultHandler.INVARIANT_A_SHARE_PREVIEWS();
    }

    function invariantMetaVault__AssetsPreviews() public view {
        vaultHandler.INVARIANT_B_ASSET_PREVIEWS();
    }

    function invariantMetaVault__InternalAccounting() public view {
        vaultHandler.INVARIANT_C_TOTAL_SUPPLY();
        vaultHandler.INVARIANT_D_TOTAL_IDLE();
        vaultHandler.INVARIANT_E_TOTAL_DEBT();
        vaultHandler.INVARIANT_F_TOTAL_ASSETS();
        vaultHandler.INVARIANT_G_TOTAL_DEPOSITS();
        vaultHandler.INVARIANT_H_TOKEN_BALANCE();
    }

    function invariantMetaVault__SharePrice() public view {
        vaultHandler.INVARIANT_I_SHARE_PRICE();
    }

    function invariantMetaVault__CallSummary() public view {
        vaultHandler.callSummary();
    }
}
