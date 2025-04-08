//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    DivestSuperform, InvestSuperform, LiquidateSuperform, SuperformGateway
} from "crosschain/SuperformGateway/Lib.sol";

import { SUPERFORM_ROUTER_BASE, SUPERFORM_SUPERPOSITIONS_BASE, USDCE_BASE, USDCE_BASE } from "helpers/AddressBook.sol";
import {
    IBaseRouter,
    IHurdleRateOracle,
    IMetaVault,
    ISharePriceOracle,
    ISuperPositions,
    ISuperformFactory,
    ISuperformGateway
} from "interfaces/Lib.sol";
import {
    AssetsManager,
    ERC7540Engine,
    ERC7540EngineReader,
    ERC7540EngineSignatures,
    EmergencyAssetsManager,
    MetaVaultReader
} from "modules/Lib.sol";
import { MetaVault } from "src/MetaVault.sol";
import { VaultConfig } from "types/Lib.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Script, console} from "forge-std/Script.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract TestRedeemScriptWeth is Script , StdCheats{
    using SafeTransferLib for address;
    VaultConfig public config;
    IMetaVault public vault;
    ISuperformGateway public gateway;
    ERC7540Engine public engine;
    ERC7540EngineReader public engineReader;
    ERC7540EngineSignatures public engineSignatures;
    AssetsManager public assetManager;
    EmergencyAssetsManager public emergencyAssetsManager;

    MetaVaultReader public metaVaultReader;

    uint256 deployerPrivateKey;
    address hurdleRateOracleAddress;

    address adminAndOwnerRole;
    address relayerRole;
    address emergencyAdminRole;
    address managerAddressRole;

    address vaultAddress;
    address constant callerAddress = 0x80DB09D92E234B1B2EE6ed40BB729DF3B27e2F60;

    function run() public {
        

        hurdleRateOracleAddress = vm.envAddress("HURDLE_RATE_ORACLE_ADDRESS");

        adminAndOwnerRole = vm.envAddress("ADMIN_AND_OWNER_ROLE");
        relayerRole = vm.envAddress("RELAYER_ROLE");
        emergencyAdminRole = vm.envAddress("EMERGENCY_ADMIN_ROLE");
        managerAddressRole = vm.envAddress("MANAGER_ADDRESS_ROLE");


        vm.startPrank(callerAddress);

        console.log("DEPLOYING NEW VAULT...");

        config = VaultConfig({
            asset: USDCE_BASE,
            name: "maxUSDC Vault",
            symbol: "maxUSDC",
            managementFee: 100,
            performanceFee: 2000,
            oracleFee: 50,
            hurdleRateOracle: IHurdleRateOracle(hurdleRateOracleAddress),
            sharesLockTime: 0,
            superPositions: ISuperPositions(SUPERFORM_SUPERPOSITIONS_BASE),
            treasury: makeAddr("treasury"),
            signerRelayer: relayerRole,
            owner: adminAndOwnerRole
        });

        MetaVault _vault = new MetaVault(config);
        vault = IMetaVault(address(_vault));


        InvestSuperform invest = new InvestSuperform();

        DivestSuperform divest = new DivestSuperform();

        LiquidateSuperform liquidate = new LiquidateSuperform();

        SuperformGateway _gateway = new SuperformGateway(
            IMetaVault(vault),
            IBaseRouter(SUPERFORM_ROUTER_BASE),
            ISuperPositions(SUPERFORM_SUPERPOSITIONS_BASE),
            adminAndOwnerRole
        );
        gateway = ISuperformGateway(address(_gateway));


        bytes4[] memory investSelectors = invest.selectors();

        _gateway.addFunctions(investSelectors, address(invest), false);

        bytes4[] memory divestSelectors = divest.selectors();
   
        _gateway.addFunctions(divestSelectors, address(divest), false);

        bytes4[] memory liquidateSelectors = liquidate.selectors();

        _gateway.addFunctions(liquidateSelectors, address(liquidate), false);

        vault.setGateway(address(gateway));


        engine = new ERC7540Engine();
        bytes4[] memory engineSelectors = engine.selectors();
        vault.addFunctions(engineSelectors, address(engine), false);

        engineReader = new ERC7540EngineReader();
        bytes4[] memory engineReaderSelectors = engineReader.selectors();
        vault.addFunctions(engineReaderSelectors, address(engineReader), false);

        engineSignatures = new ERC7540EngineSignatures();
        bytes4[] memory engineSignaturesSelectors = engineSignatures.selectors();
        vault.addFunctions(engineSignaturesSelectors, address(engineSignatures), false);

        assetManager = new AssetsManager();
        bytes4[] memory assetManagerSelectors = assetManager.selectors();
        vault.addFunctions(assetManagerSelectors, address(assetManager), false);

        emergencyAssetsManager = new EmergencyAssetsManager();
        bytes4[] memory emergencyAssetsManagerSelectors = emergencyAssetsManager.selectors();
        vault.addFunctions(emergencyAssetsManagerSelectors, address(emergencyAssetsManager), false);

        metaVaultReader = new MetaVaultReader();
        bytes4[] memory metaVaultReaderSelectors = metaVaultReader.selectors();
        vault.addFunctions(metaVaultReaderSelectors, address(metaVaultReader), false);


        vault.grantRoles(managerAddressRole, vault.MANAGER_ROLE());

        vault.grantRoles(relayerRole, vault.RELAYER_ROLE());
        gateway.grantRoles(relayerRole, gateway.RELAYER_ROLE());


        vault.grantRoles(emergencyAdminRole, vault.EMERGENCY_ADMIN_ROLE());

        vault.setDustThreshold(3_000_000);
      
        //// TEST STARTS HERE
        console.log("IMPERSONATING LIVE VAULT WITH NEW VAULT...");
        deal(USDCE_BASE, callerAddress, 100 ether);
        vm.startPrank(callerAddress);
        vaultAddress = vm.envAddress("METAVAULT_ADDRESS");
        IMetaVault vault2 = IMetaVault(vaultAddress);
        // OUR CONTRACT IMPERSONATES THE ALREADY EXISTING CONTRACT
        vm.etch(vaultAddress, address(vault).code);
        USDCE_BASE.safeApprove(address(vault2), type(uint256).max);
        vault2.requestDeposit(10_000_000, callerAddress, callerAddress);
    }
}
