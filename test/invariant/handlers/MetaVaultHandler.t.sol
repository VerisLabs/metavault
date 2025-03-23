// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { MockERC20 } from "../../helpers/mock/MockERC20.sol";
import { MockERC4626Oracle } from "../../helpers/mock/MockERC4626Oracle.sol";
import { BaseHandler, Vaults, console2 } from "./base/BaseHandler.t.sol";

import { IMetaVault, ISharePriceOracle, ProcessRedeemRequestParams } from "interfaces/IMetaVault.sol";
import { ERC7540Engine } from "modules/Lib.sol";
import "types/Lib.sol";

contract MetaVaultHandler is BaseHandler {
    IMetaVault vault;
    MockERC20 token;
    MockERC4626Oracle oracle;
    address superAdmin;

    ////////////////////////////////////////////////////////////////
    ///                      GHOST VARIABLES                     ///
    ////////////////////////////////////////////////////////////////

    // TODO:
    // 1.Add more ghost variables(invariants)
    // 2.Add more entry points(metavault interactions; charge fees, settle, invest, divest...)
    uint256 public expectedTotalSupply;
    uint256 public actualTotalSupply;

    uint256 public expectedTotalAssets;
    uint256 public actualTotalAssets;

    uint256 public expectedTotalIdle;
    uint256 public actualTotalIdle;

    uint256 public expectedTotalDebt;
    uint256 public actualTotalDebt;

    uint256 public expectedTotalDeposits;
    uint256 public actualTotalDeposits;

    uint256 public expectedSharePrice;
    uint256 public actualSharePrice;

    uint256 public expectedShares;
    uint256 public actualShares;

    uint256 public expectedAssets;
    uint256 public actualAssets;

    uint256 public expectedBalance;
    uint256 public actualBalance;

    uint256 public sharePriceDelta;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////
    constructor(IMetaVault _vault, MockERC20 _token, address _superAdmin, MockERC4626Oracle _oracle) {
        vault = _vault;
        token = _token;
        superAdmin = _superAdmin;
        oracle = _oracle;
    }

    ////////////////////////////////////////////////////////////////
    ///                      ENTRY POINTS                        ///
    ////////////////////////////////////////////////////////////////
    function deposit(uint256 amount) public createActor countCall("deposit") {
        amount = bound(amount, 0, 100_000e6 - vault.totalAssets());
        if (amount == 0) return;
        if (currentActor == address(vault)) return;

        deal(address(token), currentActor, amount);

        //uint256 previousSharePrice = vault.sharePrice();
        expectedShares = vault.convertToShares(amount);
        if (expectedShares == 0) {
            actualShares = 0;
            return;
        }
        expectedBalance = actualBalance + amount;
        expectedTotalSupply = actualTotalSupply + expectedShares;
        expectedTotalAssets = actualTotalAssets + amount;
        expectedTotalDeposits = actualTotalDeposits + amount;
        expectedTotalIdle = actualTotalIdle + amount;
        expectedTotalDebt = 0;
        expectedSharePrice = ((10 ** vault.decimals()) * (expectedTotalAssets + 1)) / (expectedTotalSupply + 1);

        vm.startPrank(currentActor);
        token.approve(address(vault), type(uint256).max);
        vault.requestDeposit(amount, currentActor, currentActor);
        actualShares = vault.deposit(amount, currentActor);
        vm.stopPrank();

        actualBalance = token.balanceOf(address(vault));
        actualTotalSupply = vault.totalSupply();
        actualTotalAssets = vault.totalAssets();
        actualTotalDeposits = vault.totalDeposits();
        actualTotalDebt = vault.totalDebt();
        actualTotalIdle = vault.totalDeposits();
        actualSharePrice = vault.sharePrice();
    }

    function invest(uint256 vaultIndexSeed, uint256 amount) public useVault(vaultIndexSeed) countCall("invest") {
        amount = bound(amount, 0, vault.totalIdle());
        if (amount == 0 || currentVault.vault == address(0)) return; // Check if currentVault is empty

        vm.startPrank(superAdmin);
        expectedBalance = actualBalance;
        expectedTotalIdle = actualTotalIdle - amount;
        expectedTotalAssets = actualTotalAssets;
        expectedTotalDeposits = actualTotalDeposits;
        expectedTotalDebt = actualTotalDebt + amount;
        expectedTotalSupply = actualTotalSupply;
        expectedSharePrice = ((10 ** vault.decimals()) * (expectedTotalAssets + 1)) / (expectedTotalSupply + 1);

        if (currentVault.chainId == block.chainid) {
            vault.investSingleDirectSingleVault(currentVault.vault, amount, 0);
        } else {
            SingleXChainSingleVaultStateReq memory req;
            req.superformData.superformId = currentVault.superformId;
            req.superformData.amount = amount;
            vault.investSingleXChainSingleVault(req);
        }

        actualBalance = token.balanceOf(address(vault));
        actualTotalSupply = vault.totalSupply();
        actualTotalAssets = vault.totalAssets();
        actualTotalDeposits = vault.totalDeposits();
        actualTotalDebt = vault.totalDebt();
        actualTotalIdle = vault.totalDeposits();
        actualSharePrice = vault.sharePrice();
        vm.stopPrank();
    }

    function requestRedeem(uint256 actorSeed, uint256 shares) public useActor(actorSeed) countCall("requestRedeem") {
        shares = bound(shares, 0, vault.balanceOf(currentActor));
        if (shares == 0) return;
        if (currentActor == address(vault)) return;

        expectedSharePrice = ((10 ** vault.decimals()) * (expectedTotalAssets + 1)) / (expectedTotalSupply + 1);

        vm.startPrank(currentActor);
        actualAssets = vault.requestRedeem(shares, currentActor, currentActor);
        vm.stopPrank();

        actualBalance = token.balanceOf(address(vault));
        actualTotalSupply = vault.totalSupply();
        actualTotalAssets = vault.totalAssets();
        actualTotalDeposits = vault.totalDeposits();
        actualTotalDebt = vault.totalDebt();
        actualTotalIdle = vault.totalDeposits();
        actualSharePrice = vault.sharePrice();
    }

    function redeem(uint256 actorSeed, uint256 shares) public useActor(actorSeed) countCall("redeem") {
        shares = bound(shares, 0, vault.claimableRedeemRequest(currentActor));
        if (shares == 0) return;
        if (currentActor == address(vault)) return;

        vm.startPrank(currentActor);
        actualAssets = vault.redeem(shares, currentActor, currentActor);
        expectedBalance = actualBalance - actualAssets;
        vm.stopPrank();

        actualBalance = token.balanceOf(address(vault));
        actualTotalSupply = vault.totalSupply();
        actualTotalAssets = vault.totalAssets();
        actualTotalDeposits = vault.totalDeposits();
        actualTotalDebt = vault.totalDebt();
        actualTotalIdle = vault.totalDeposits();
        actualSharePrice = vault.sharePrice();
    }

    function gain(uint256 assets) external countCall("gain") {
        if (vault.totalSupply() == 0) return;
        assets = bound(assets, 0, 100_000e6 - vault.totalAssets());
        vm.startPrank(superAdmin);
        deal(address(token), superAdmin, assets);
        expectedBalance = actualBalance + assets;
        expectedTotalIdle = actualTotalIdle + assets;
        expectedTotalAssets = actualTotalAssets + assets;
        expectedTotalDeposits = actualTotalDeposits + assets;
        expectedSharePrice = ((10 ** vault.decimals()) * (expectedTotalAssets + 1)) / (expectedTotalSupply + 1);
        vault.donate(assets);
        actualBalance = token.balanceOf(address(vault));
        actualTotalSupply = vault.totalSupply();
        actualTotalAssets = vault.totalAssets();
        actualTotalDeposits = vault.totalDeposits();
        actualTotalDebt = vault.totalDebt();
        actualTotalIdle = vault.totalDeposits();
        actualSharePrice = vault.sharePrice();
    }

    function lose(uint256 assets) external countCall("lose") {
        if (vault.totalSupply() == 0) return;
        assets = bound(assets, 0, vault.totalAssets());
        vm.startPrank(superAdmin);
        expectedBalance = actualBalance;
        expectedTotalIdle = actualTotalIdle;
        expectedTotalAssets = actualTotalAssets;
        expectedTotalDeposits = actualTotalDeposits;
        expectedTotalSupply = actualTotalSupply + vault.convertToShares(assets);
        expectedSharePrice = ((10 ** vault.decimals()) * (expectedTotalAssets + 1)) / (expectedTotalSupply + 1);
        (bool s,) = address(vault).call(
            abi.encodeWithSignature("mint(address,uint256)", makeAddr("random"), vault.convertToShares(assets))
        );
        actualBalance = token.balanceOf(address(vault));
        actualTotalSupply = vault.totalSupply();
        actualTotalAssets = vault.totalAssets();
        actualTotalDeposits = vault.totalDeposits();
        actualTotalDebt = vault.totalDebt();
        actualTotalIdle = vault.totalDeposits();
        actualSharePrice = vault.sharePrice();
        vm.stopPrank();
    }

    function addVault() external countCall("addVault") createVault(address(token), oracle) {
        vm.startPrank(superAdmin);

        expectedBalance = actualBalance;
        expectedTotalIdle = actualTotalIdle;
        expectedTotalAssets = actualTotalAssets;
        expectedTotalDeposits = actualTotalDeposits;
        expectedTotalSupply = actualTotalSupply;
        expectedSharePrice = ((10 ** vault.decimals()) * (expectedTotalAssets + 1)) / (expectedTotalSupply + 1);

        // Use the vault created by the createVault modifier
        vault.addVault(
            uint32(currentVault.chainId),
            currentVault.superformId,
            currentVault.vault,
            vault.decimals(),
            ISharePriceOracle(address(oracle))
        );

        actualBalance = token.balanceOf(address(vault));
        actualTotalSupply = vault.totalSupply();
        actualTotalAssets = vault.totalAssets();
        actualTotalDeposits = vault.totalDeposits();
        actualTotalDebt = vault.totalDebt();
        actualTotalIdle = vault.totalDeposits();
        actualSharePrice = vault.sharePrice();

        vm.stopPrank();
    }

    function processRedeemRequest(uint256 actorSeed, uint256 shares) public countCall("processRedeemRequest") {
        address controller = getActor(actorSeed);
        shares = bound(shares, 0, vault.pendingRedeemRequest(controller));
        uint256 assets = vault.convertToAssets(shares);
        if (assets >= vault.totalWithdrawableAssets()) return;
        ERC7540Engine.ProcessRedeemRequestCache memory cachedRoute =
            vault.previewWithdrawalRoute(controller, shares, false);
        assets = cachedRoute.assets;
        if (shares == 0) return;

        ProcessRedeemRequestParams memory params;
        params.controller = controller;
        params.shares = shares;

        // Fill params based on liquidation type of cachedRoute
        if (cachedRoute.isMultiChain && cachedRoute.isMultiVault) {
            MultiXChainMultiVaultWithdraw memory _mXmV;
            params.mXmV = _mXmV;
        } else if (cachedRoute.isMultiChain && !cachedRoute.isMultiVault) {
            MultiXChainSingleVaultWithdraw memory _mXsV;
            params.mXsV = _mXsV;
        } else if (cachedRoute.isSingleChain && cachedRoute.isMultiVault) {
            SingleXChainMultiVaultWithdraw memory _sXmV;
            params.sXmV = _sXmV;
        } else if (cachedRoute.isSingleChain && !cachedRoute.isMultiVault) {
            SingleXChainSingleVaultWithdraw memory _sXsV;
            params.sXsV = _sXsV;
        } else {
            
        }

        expectedTotalAssets = actualTotalAssets - assets;
        expectedTotalIdle = actualTotalIdle - assets;
        expectedTotalDeposits = actualTotalDeposits - assets;
        expectedTotalSupply = actualTotalSupply - shares;
        expectedSharePrice = ((10 ** vault.decimals()) * (expectedTotalAssets + 1)) / (expectedTotalSupply + 1);
        vm.startPrank(superAdmin);

        vault.processRedeemRequest(params);
        vm.stopPrank();
        actualBalance = token.balanceOf(address(vault));
        actualTotalSupply = vault.totalSupply();
        actualTotalAssets = vault.totalAssets();
        actualTotalDeposits = vault.totalDeposits();
        actualTotalDebt = vault.totalDebt();
        actualTotalIdle = vault.totalDeposits();
        actualSharePrice = vault.sharePrice();
    }

    ////////////////////////////////////////////////////////////////
    ///                      INVARIANTS                          ///
    ////////////////////////////////////////////////////////////////
    function INVARIANT_A_SHARE_PREVIEWS() public view {
        assertLe(actualShares, expectedShares);
    }

    function INVARIANT_B_ASSET_PREVIEWS() public view {
        assertGe(actualAssets, expectedAssets);
    }

    function INVARIANT_C_TOTAL_SUPPLY() public view {
        assertEq(actualTotalSupply, expectedTotalSupply);
    }

    function INVARIANT_D_TOTAL_IDLE() public view {
        assertEq(actualTotalIdle, expectedTotalIdle);
    }

    function INVARIANT_E_TOTAL_DEBT() public view {
        assertEq(actualTotalDebt, expectedTotalDebt);
    }

    function INVARIANT_F_TOTAL_ASSETS() public view {
        assertEq(actualTotalAssets, expectedTotalAssets);
    }

    function INVARIANT_G_TOTAL_DEPOSITS() public view {
        assertEq(actualTotalDeposits, expectedTotalDeposits);
    }

    function INVARIANT_H_TOKEN_BALANCE() public view {
        assertEq(actualBalance, expectedBalance);
    }

    function INVARIANT_I_SHARE_PRICE() public view {
        assertApproxEqRel(actualSharePrice, expectedSharePrice, 1e16);
        // NOTE: share price can dramatically change in some edge cases
        // assertLe(sharePriceDelta, 100,  "invariant: share price delta"); // 1%
    }

    ////////////////////////////////////////////////////////////////
    ///                      HELPERS                             ///
    ////////////////////////////////////////////////////////////////

    function getEntryPoints() public pure override returns (bytes4[] memory) {
        bytes4[] memory _entryPoints = new bytes4[](7);
        _entryPoints[0] = this.deposit.selector;
        _entryPoints[1] = this.requestRedeem.selector;
        _entryPoints[2] = this.redeem.selector;
        _entryPoints[3] = this.gain.selector;
        _entryPoints[4] = this.lose.selector;
        _entryPoints[5] = this.processRedeemRequest.selector;
        _entryPoints[6] = this.addVault.selector;
        //  _entryPoints[7] = this.invest.selector;
        return _entryPoints;
    }

    function callSummary() public view override {
        console2.log("");
        console2.log("");
        console2.log("Call summary:");
        console2.log("-------------------");
        console2.log("deposit", calls["deposit"]);
        console2.log("requestRedeem", calls["requestRedeem"]);
        console2.log("processRedeemRequest", calls["processRedeemRequest"]);
        console2.log("redeem", calls["redeem"]);
        console2.log("lose", calls["lose"]);
        console2.log("addVault", calls["addVault"]);
        console2.log("invest", calls["invest"]);
        console2.log("-------------------");
    }
}
