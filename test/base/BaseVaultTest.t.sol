import { BaseTest } from "./BaseTest.t.sol";
import {
    EXACTLY_USDC_VAULT_ID_OPTIMISM,
    SUPERFORM_FACTORY_POLYGON,
    SUPERFORM_ROUTER_POLYGON,
    SUPERFORM_SUPERPOSITIONS_POLYGON,
    USDCE_POLYGON
} from "src/helpers/AddressBook.sol";
import { IBaseRouter, IERC4626Oracle, ISuperPositions, ISuperformFactory } from "src/interfaces/Lib.sol";
import { VaultConfig } from "src/types/Lib.sol";

contract BaseVaultTest is BaseTest {
    VaultConfig public config;

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
}
