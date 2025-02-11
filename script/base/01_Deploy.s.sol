//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    DivestSuperform, InvestSuperform, LiquidateSuperform, SuperformGateway
} from "crosschain/SuperformGateway/Lib.sol";
import { Script, console2 } from "forge-std/Script.sol";

import { SUPERFORM_ROUTER_BASE, SUPERFORM_SUPERPOSITIONS_BASE, USDCE_BASE, WETH_BASE } from "helpers/AddressBook.sol";
import {
    IBaseRouter,
    IHurdleRateOracle,
    IMetaVault,
    ISharePriceOracle,
    ISuperPositions,
    ISuperformFactory,
    ISuperformGateway
} from "interfaces/Lib.sol";
import { AssetsManager, ERC7540Engine } from "modules/Lib.sol";
import { MetaVault } from "src/MetaVault.sol";
import { VaultConfig } from "types/Lib.sol";

contract DeployScript is Script {
    VaultConfig public config;
    IMetaVault public vault;
    ISuperformGateway public gateway;
    ERC7540Engine public engine;
    AssetsManager public assetManager;

    uint256 deployerPrivateKey;
    address hurdleRateOracleAddress;

    address adminAndOwnerRole;
    address relayerRole;
    address emergencyAdminRole;
    address managerAddressRole;

    function run() public {
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        hurdleRateOracleAddress = vm.envAddress("HURDLE_RATE_ORACLE_ADDRESS");

        adminAndOwnerRole = vm.envAddress("ADMIN_AND_OWNER_ROLE");
        relayerRole = vm.envAddress("RELAYER_ROLE");
        emergencyAdminRole = vm.envAddress("EMERGENCY_ADMIN_ROLE");
        managerAddressRole = vm.envAddress("MANAGER_ADDRESS_ROLE");
        vm.startBroadcast(deployerPrivateKey);

        config = VaultConfig({
            asset: USDCE_BASE,
            name: "MaxUSD Vault",
            symbol: "maxUSD",
            managementFee: 100,
            performanceFee: 2000,
            oracleFee: 50,
            hurdleRateOracle: IHurdleRateOracle(hurdleRateOracleAddress),
            sharesLockTime: 30 days,
            superPositions: ISuperPositions(SUPERFORM_SUPERPOSITIONS_BASE),
            treasury: makeAddr("treasury"),
            signerRelayer: relayerRole,
            owner: adminAndOwnerRole
        });

        MetaVault _vault = new MetaVault(config);
        vault = IMetaVault(address(_vault));

        // Deploy gateway
        InvestSuperform invest = new InvestSuperform();
        DivestSuperform divest = new DivestSuperform();
        LiquidateSuperform liquidate = new LiquidateSuperform();
        SuperformGateway _gateway = new SuperformGateway(
            IMetaVault(vault),
            IBaseRouter(SUPERFORM_ROUTER_BASE),
            ISuperPositions(SUPERFORM_SUPERPOSITIONS_BASE),
            adminAndOwnerRole
        );
        bytes4[] memory investSelectors = invest.selectors();
        _gateway.addFunctions(investSelectors, address(invest), false);
        bytes4[] memory divestSelectors = divest.selectors();
        _gateway.addFunctions(divestSelectors, address(divest), false);
        bytes4[] memory liquidateSelectors = liquidate.selectors();
        _gateway.addFunctions(liquidateSelectors, address(liquidate), false);
        gateway = ISuperformGateway(address(_gateway));

        // Set gatway
        vault.setGateway(address(gateway));

        // Add vault modules
        engine = new ERC7540Engine();
        bytes4[] memory engineSelectors = engine.selectors();
        vault.addFunctions(engineSelectors, address(engine), false);

        assetManager = new AssetsManager();
        bytes4[] memory assetManagerSelectors = assetManager.selectors();
        vault.addFunctions(assetManagerSelectors, address(assetManager), false);

        // Grant roles
        vault.grantRoles(managerAddressRole, vault.MANAGER_ROLE());
        vault.grantRoles(relayerRole, vault.RELAYER_ROLE());
        vault.grantRoles(emergencyAdminRole, vault.EMERGENCY_ADMIN_ROLE());

        console2.log("Vault deployed at: ", address(vault));
        console2.log("Gateway deployed at: ", address(gateway));
        console2.log("Engine deployed at: ", address(engine));
        console2.log("AssetManager deployed at: ", address(assetManager));
        console2.log("InvestSuperform deployed at: ", address(invest));
        console2.log("DivestSuperform deployed at: ", address(divest));
        console2.log("LiquidateSuperform deployed at: ", address(liquidate));

        vm.stopBroadcast();
    }
}
