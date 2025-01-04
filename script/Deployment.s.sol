// //SPDX-License-Identifier: MIT
// pragma solidity ^0.8.0;

// import { MaxLzEndpoint, SharePriceOracle, SuperformGateway } from "crosschain/Lib.sol";

// import { Script, console2 } from "forge-std/Script.sol";

// import { ISuperPositions, ISuperformGateway } from "interfaces/Lib.sol";
// import { ProxyAdmin } from "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
// import { TransparentUpgradeableProxy } from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
// import { MetaVault } from "src/MetaVault.sol";
// import { SUPERFORM_ROUTER_BASE, SUPERFORM_SUPERPOSITIONS_BASE, USDCE_BASE } from "src/helpers/AddressBook.sol";
// import { ERC7540Engine } from "src/modules/Lib.sol";
// import { VaultConfig } from "types/Lib.sol";

// contract DeploymentScript is Script {
//     VaultConfig public config;
//     MetaVault public vault;
//     address public vaultAdmin;
//     SharePriceOracle public oracle;
//     MaxLzEndpoint public maxLzEndpoint;
//     SuperformGateway public gateway;
//     ERC7540Engine public engine;

//     function run() public {
//         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
//         vm.startBroadcast(deployerPrivateKey);

//         vaultAdmin = vm.envAddress("VAULT_ADMIN");
//         config = VaultConfig({
//             asset: USDCE_BASE,
//             name: "MaxApyCrossUSDCeVault",
//             symbol: "maxcUSDCE",
//             managementFee: 100,
//             performanceFee: 2000,
//             oracleFee: 300,
//             assetHurdleRate: 400,
//             sharesLockTime: 500,
//             superPositions: ISuperPositions(SUPERFORM_SUPERPOSITIONS_BASE),
//             treasury: vaultAdmin,
//             signerRelayer: vaultAdmin
//         });

//         vault = new MetaVault(config);
//         ProxyAdmin admin = new ProxyAdmin(vaultAdmin);

//         SuperformGateway implementation = new SuperformGateway();
//         TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
//             address(implementation),
//             address(admin),
//             abi.encodeWithSelector(
//                 SuperformGateway.initialize.selector,
//                 address(vault),
//                 vaultAdmin,
//                 SUPERFORM_ROUTER_BASE,
//                 SUPERFORM_SUPERPOSITIONS_BASE
//             )
//         );

//         gateway = SuperformGateway(address(proxy));
//         gateway.grantRoles(vaultAdmin, gateway.RELAYER_ROLE());
//         vault.setGateway(ISuperformGateway(address(gateway)));

//         engine = new ERC7540Engine();
//         vault.addFunction(ERC7540Engine.processRedeemRequest.selector, address(engine), false);
//         //       vault.addFunction(
//         //           ERC7540Engine.processRedeemRequestWithSignature.selector,
//         //           address(engine),
//         //           false
//         //       );
//         vault.addFunction(ERC7540Engine.previewWithdrawalRoute.selector, address(engine), false);

//         oracle = new SharePriceOracle(uint64(block.chainid), address(0x429796dAc057E7C15724196367007F1e9Cff82F9));

//         maxLzEndpoint = new MaxLzEndpoint(
//             address(0x429796dAc057E7C15724196367007F1e9Cff82F9), //owner
//             address(0x1a44076050125825900e736c501f859c50fE728c), // LZEndpoint
//             address(oracle)
//         );
//         oracle.grantRole(address(maxLzEndpoint), oracle.ENDPOINT_ROLE());

//         vault.grantRoles(vaultAdmin, vault.MANAGER_ROLE());
//         vault.grantRoles(address(oracle), vault.ORACLE_ROLE());
//         vault.grantRoles(vaultAdmin, vault.RELAYER_ROLE());
//         vault.grantRoles(vaultAdmin, vault.EMERGENCY_ADMIN_ROLE());

//         console2.log("Vault deployed at: ", address(vault));
//         console2.log("Gateway deployed at: ", address(gateway));
//         console2.log("Oracle deployed at: ", address(oracle));
//         console2.log("MaxLzEndpoint deployed at: ", address(maxLzEndpoint));

//         vm.stopBroadcast();
//     }
// }
