import { BaseTest } from "./BaseTest.t.sol";

import { MockHurdleRateOracle } from "../helpers/mock/MockHurdleRateOracle.sol";
import { MockSignerRelayer } from "../helpers/mock/MockSignerRelayer.sol";
import {
    DivestSuperform, InvestSuperform, LiquidateSuperform, SuperformGateway
} from "crosschain/SuperformGateway/Lib.sol";
import {
    IBaseRouter,
    IHurdleRateOracle,
    IMetaVault,
    ISharePriceOracle,
    ISuperPositions,
    ISuperformFactory,
    ISuperformGateway
} from "interfaces/Lib.sol";

import { SuperPositionsReceiver } from "crosschain/Lib.sol";
import { ProxyAdmin } from "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { MetaVault } from "src/MetaVault.sol";
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
    IMetaVault public vault;

    function polygonUsdceVaultConfig() public returns (VaultConfig memory) {
        return VaultConfig({
            asset: USDCE_POLYGON,
            name: "MaxApyCrossUSDCeVault",
            symbol: "maxcUSDCE",
            managementFee: 0,
            performanceFee: 0,
            oracleFee: 0,
            hurdleRateOracle: IHurdleRateOracle(address(new MockHurdleRateOracle())),
            sharesLockTime: 30 days,
            superPositions: ISuperPositions(SUPERFORM_SUPERPOSITIONS_POLYGON),
            treasury: makeAddr("treasury"),
            signerRelayer: address(new MockSignerRelayer(0xA111ce))
        });
    }

    function baseChainUsdceVaultConfig() public returns (VaultConfig memory) {
        return VaultConfig({
            asset: USDCE_BASE,
            name: "MaxApyCrossUSDCeVault",
            symbol: "maxcUSDCE",
            managementFee: 0,
            performanceFee: 2000,
            oracleFee: 0,
            hurdleRateOracle: IHurdleRateOracle(address(new MockHurdleRateOracle())),
            sharesLockTime: 30 days,
            superPositions: ISuperPositions(SUPERFORM_SUPERPOSITIONS_BASE),
            treasury: makeAddr("treasury"),
            signerRelayer: address(new MockSignerRelayer(0xA111ce))
        });
    }

    function deployGatewayPolygon(address vault, address owner) public returns (ISuperformGateway) {
        ProxyAdmin admin = new ProxyAdmin(owner);
        InvestSuperform invest = new InvestSuperform();
        DivestSuperform divest = new DivestSuperform();
        LiquidateSuperform liquidate = new LiquidateSuperform();
        SuperformGateway gateway = new SuperformGateway(
            IMetaVault(vault),
            IBaseRouter(SUPERFORM_ROUTER_POLYGON),
            ISuperPositions(SUPERFORM_SUPERPOSITIONS_POLYGON)
        );
        bytes4[] memory investSelectors = invest.selectors();
        gateway.addFunctions(investSelectors, address(invest), false);
        bytes4[] memory divestSelectors = divest.selectors();
        gateway.addFunctions(divestSelectors, address(divest), false);
        bytes4[] memory liquidateSelectors = liquidate.selectors();
        gateway.addFunctions(liquidateSelectors, address(liquidate), false);
        ISuperformGateway(address(gateway)).setRecoveryAddress(
            address(new SuperPositionsReceiver(8453, address(gateway), SUPERFORM_SUPERPOSITIONS_BASE))
        );
        return ISuperformGateway(address(gateway));
    }

    function deployGatewayBase(address vault, address owner) public returns (ISuperformGateway) {
        ProxyAdmin admin = new ProxyAdmin(owner);
        InvestSuperform invest = new InvestSuperform();
        DivestSuperform divest = new DivestSuperform();
        LiquidateSuperform liquidate = new LiquidateSuperform();
        SuperformGateway gateway = new SuperformGateway(
            IMetaVault(vault), IBaseRouter(SUPERFORM_ROUTER_BASE), ISuperPositions(SUPERFORM_SUPERPOSITIONS_BASE)
        );
        bytes4[] memory investSelectors = invest.selectors();
        gateway.addFunctions(investSelectors, address(invest), false);
        bytes4[] memory divestSelectors = divest.selectors();
        gateway.addFunctions(divestSelectors, address(divest), false);
        bytes4[] memory liquidateSelectors = liquidate.selectors();
        gateway.addFunctions(liquidateSelectors, address(liquidate), false);
        ISuperformGateway(address(gateway)).setRecoveryAddress(
            address(new SuperPositionsReceiver(8453, address(gateway), SUPERFORM_SUPERPOSITIONS_BASE))
        );
        return ISuperformGateway(address(gateway));
    }

    function _depositAtomic(uint256 assets, address receiver) internal returns (uint256 _shares) {
        bytes[] memory callDatas = new bytes[](2);
        callDatas[0] = abi.encodeWithSelector(MetaVault.requestDeposit.selector, assets, receiver, users.alice);
        callDatas[1] = abi.encodeWithSignature("deposit(uint256,address)", assets, receiver);
        bytes[] memory returnData = vault.multicall(callDatas);
        return abi.decode(returnData[1], (uint256));
    }

    function _mintAtomic(uint256 shares, address receiver) internal returns (uint256 _assets) {
        bytes[] memory callDatas = new bytes[](2);
        uint256 assets = vault.convertToAssets(shares);
        callDatas[0] = abi.encodeWithSelector(MetaVault.requestDeposit.selector, assets, receiver, users.alice);
        callDatas[1] = abi.encodeWithSignature("mint(uint256,address)", shares, receiver);
        bytes[] memory returnData = vault.multicall(callDatas);
        return abi.decode(returnData[1], (uint256));
    }
}
