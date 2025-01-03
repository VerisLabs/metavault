import { BaseTest } from "./BaseTest.t.sol";

import { MockSignerRelayer } from "../helpers/mock/MockSignerRelayer.sol";
import { SuperformGateway } from "crosschain/Lib.sol";
import {
    IBaseRouter,
    IMetaVault,
    ISharePriceOracle,
    ISuperPositions,
    ISuperformFactory,
    ISuperformGateway
} from "interfaces/Lib.sol";

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
            assetHurdleRate: 600,
            sharesLockTime: 30 days,
            superPositions: ISuperPositions(SUPERFORM_SUPERPOSITIONS_POLYGON),
            treasury: makeAddr("treasury"),
            recoveryAddress: makeAddr("recoveryAddress"),
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
            assetHurdleRate: 600,
            sharesLockTime: 30 days,
            superPositions: ISuperPositions(SUPERFORM_SUPERPOSITIONS_BASE),
            treasury: makeAddr("treasury"),
            recoveryAddress: makeAddr("recoveryAddress"),
            signerRelayer: address(new MockSignerRelayer(0xA111ce))
        });
    }

    function deployGatewayPolygon(address vault, address owner) public returns (SuperformGateway) {
        ProxyAdmin admin = new ProxyAdmin(owner);
        SuperformGateway implementation = new SuperformGateway();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            owner,
            abi.encodeWithSelector(
                SuperformGateway.initialize.selector,
                vault,
                owner,
                SUPERFORM_ROUTER_POLYGON,
                SUPERFORM_SUPERPOSITIONS_POLYGON,
                address(0)
            )
        );
        return SuperformGateway(address(proxy));
    }

    function deployGatewayBase(address vault, address owner) public returns (SuperformGateway) {
        ProxyAdmin admin = new ProxyAdmin(owner);
        SuperformGateway implementation = new SuperformGateway();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            owner,
            abi.encodeWithSelector(
                SuperformGateway.initialize.selector,
                vault,
                owner,
                SUPERFORM_ROUTER_BASE,
                SUPERFORM_SUPERPOSITIONS_BASE,
                address(0)
            )
        );
        return SuperformGateway(address(proxy));
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
