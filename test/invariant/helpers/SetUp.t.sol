// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { MockERC20 } from "../../helpers/mock/MockERC20.sol";

import { MockHurdleRateOracle } from "../../helpers/mock/MockHurdleRateOracle.sol";

import { MetaVaultHandler } from "../handlers/MetaVaultHandler.t.sol";

import { MockERC4626Oracle } from "../../helpers/mock/MockERC4626Oracle.sol";
import { MockSignerRelayer } from "../../helpers/mock/MockSignerRelayer.sol";
import { MockSuperPositions } from "../../helpers/mock/MockSuperPositions.sol";
import { MockSuperformRouter } from "../../helpers/mock/MockSuperformRouter.sol";

import { SuperPositionsReceiver } from "crosschain/Lib.sol";
import {
    DivestSuperform, InvestSuperform, LiquidateSuperform, SuperformGateway
} from "crosschain/SuperformGateway/Lib.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { Test } from "forge-std/Test.sol";
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

contract SetUp is StdInvariant, Test {
    MockERC20 token;
    IMetaVault vault;
    MockSuperformRouter router;
    MockSuperPositions superPositions;
    VaultConfig config;
    ISuperformGateway gateway;
    ERC7540Engine engine;
    MockERC4626Oracle oracle;
    AssetsManager manager;
    MetaVaultHandler vaultHandler;
    address superAdmin = makeAddr("superAdmin");
    address treasury = makeAddr("treasury");

    function _setUpToken() internal {
        token = new MockERC20("MockERC20", "MERC", 6);
        vm.label(address(token), "USDC");
    }

    function _setUpVault() internal {
        vm.startPrank(superAdmin);
        superPositions = new MockSuperPositions();
        router = new MockSuperformRouter();
        oracle = new MockERC4626Oracle();
        config = VaultConfig({
            asset: address(token),
            name: "MetaUsdceVault",
            symbol: "metaUSDCe",
            managementFee: 100,
            performanceFee: 2000,
            oracleFee: 50,
            hurdleRateOracle: IHurdleRateOracle(address(new MockHurdleRateOracle())),
            sharesLockTime: 0,
            superPositions: ISuperPositions(address(superPositions)),
            treasury: treasury,
            signerRelayer: address(new MockSignerRelayer(0xA111ce)),
            owner: superAdmin
        });
        vault = IMetaVault(address(new MetaVault(config)));
        router.initialize(vault, ISuperPositions(address(superPositions)), vault.asset());
        gateway = deployGateway(address(vault), superAdmin);
        vaultHandler = new MetaVaultHandler(vault, token, superAdmin);
        vault.setGateway(address(gateway));
        gateway.grantRoles(superAdmin, gateway.RELAYER_ROLE());

        engine = new ERC7540Engine();
        bytes4[] memory engineSelectors = engine.selectors();
        vault.addFunctions(engineSelectors, address(engine), false);

        manager = new AssetsManager();
        bytes4[] memory managerSelectors = manager.selectors();
        vault.addFunctions(managerSelectors, address(manager), false);

        oracle = new MockERC4626Oracle();
        vault.grantRoles(superAdmin, vault.MANAGER_ROLE());
        vault.grantRoles(superAdmin, vault.ORACLE_ROLE());
        vault.grantRoles(superAdmin, vault.RELAYER_ROLE());
        vault.grantRoles(superAdmin, vault.EMERGENCY_ADMIN_ROLE());

        token.approve(address(vault), type(uint256).max);

        targetContract(address(vaultHandler));
        bytes4[] memory selectors = vaultHandler.getEntryPoints();
        targetSelector(FuzzSelector({ addr: address(vaultHandler), selectors: selectors }));
        vm.label(address(vault), "VAULT");
        vm.label(address(vaultHandler), "MVH");
        vm.stopPrank();
    }

    function deployGateway(address vault, address owner) public returns (ISuperformGateway) {
        InvestSuperform invest = new InvestSuperform();
        DivestSuperform divest = new DivestSuperform();
        LiquidateSuperform liquidate = new LiquidateSuperform();
        SuperformGateway gateway = new SuperformGateway(
            IMetaVault(vault), IBaseRouter(address(router)), ISuperPositions(address(superPositions)), superAdmin
        );
        bytes4[] memory investSelectors = invest.selectors();
        gateway.addFunctions(investSelectors, address(invest), false);
        bytes4[] memory divestSelectors = divest.selectors();
        gateway.addFunctions(divestSelectors, address(divest), false);
        bytes4[] memory liquidateSelectors = liquidate.selectors();
        gateway.addFunctions(liquidateSelectors, address(liquidate), false);
        ISuperformGateway(address(gateway)).setRecoveryAddress(
            address(new SuperPositionsReceiver(8453, address(gateway), address(superPositions), superAdmin))
        );
        return ISuperformGateway(address(gateway));
    }
}
