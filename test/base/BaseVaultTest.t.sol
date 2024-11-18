import { BaseTest } from "./BaseTest.t.sol";

import { IBaseRouter, IERC4626Oracle, ISuperPositions, ISuperformFactory } from "interfaces/Lib.sol";
import { MaxApyCrossChainVault } from "src/MaxApyCrossChainVault.sol";
import {
    EXACTLY_USDC_VAULT_ID_OPTIMISM,
    SUPERFORM_FACTORY_BASE,
    SUPERFORM_FACTORY_POLYGON,
    SUPERFORM_ROUTER_BASE,
    SUPERFORM_ROUTER_POLYGON,
    SUPERFORM_SUPERPOSITIONS_BASE,
    SUPERFORM_SUPERPOSITIONS_POLYGON,
    USDCE_BASE,
    USDCE_POLYGON
} from "src/helpers/AddressBook.sol";
import { VaultConfig } from "types/Lib.sol";

contract BaseVaultTest is BaseTest {
    VaultConfig public config;
    MaxApyCrossChainVault public vault;

    function polygonUsdceVaultConfig() public returns (VaultConfig memory) {
        return VaultConfig({
            asset: USDCE_POLYGON,
            name: "MaxApyCrossUSDCeVault",
            symbol: "maxcUSDCE",
            managementFee: 100,
            performanceFee: 2000,
            oracleFee: 300,
            assetHurdleRate: 600,
            sharesLockTime: 30 days,
            processRedeemSettlement: 1 days,
            superPositions: ISuperPositions(SUPERFORM_SUPERPOSITIONS_POLYGON),
            vaultRouter: IBaseRouter(SUPERFORM_ROUTER_POLYGON),
            factory: ISuperformFactory(SUPERFORM_FACTORY_POLYGON),
            treasury: makeAddr("treasury"),
            recoveryAddress: makeAddr("recoveryAddress"),
            signerRelayer: address(1)
        });
    }

    function baseChainUsdceVaultConfig() public returns (VaultConfig memory) {
        return VaultConfig({
            asset: USDCE_BASE,
            name: "MaxApyCrossUSDCeVault",
            symbol: "maxcUSDCE",
            managementFee: 100,
            performanceFee: 2000,
            oracleFee: 300,
            assetHurdleRate: 600,
            sharesLockTime: 30 days,
            processRedeemSettlement: 1 days,
            superPositions: ISuperPositions(SUPERFORM_SUPERPOSITIONS_BASE),
            vaultRouter: IBaseRouter(SUPERFORM_ROUTER_BASE),
            factory: ISuperformFactory(SUPERFORM_FACTORY_BASE),
            treasury: makeAddr("treasury"),
            recoveryAddress: makeAddr("recoveryAddress"),
            signerRelayer: address(1)
        });
    }

    function _depositAtomic(uint256 assets, address receiver) internal returns (uint256 _shares) {
        bytes[] memory callDatas = new bytes[](2);
        callDatas[0] =
            abi.encodeWithSelector(MaxApyCrossChainVault.requestDeposit.selector, assets, receiver, users.alice);
        callDatas[1] = abi.encodeWithSignature("deposit(uint256,address)", assets, receiver);
        bytes[] memory returnData = vault.multicall(callDatas);
        return abi.decode(returnData[1], (uint256));
    }

    function _mintAtomic(uint256 shares, address receiver) internal returns (uint256 _assets) {
        bytes[] memory callDatas = new bytes[](2);
        uint256 assets = vault.convertToAssets(shares);
        callDatas[0] =
            abi.encodeWithSelector(MaxApyCrossChainVault.requestDeposit.selector, assets, receiver, users.alice);
        callDatas[1] = abi.encodeWithSignature("mint(uint256,address)", shares, receiver);
        bytes[] memory returnData = vault.multicall(callDatas);
        return abi.decode(returnData[1], (uint256));
    }
}
