//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SuperformGateway, SharePriceOracle, MaxLzEndpoint} from "crosschain/Lib.sol";
import {VaultConfig, SingleXChainSingleVaultStateReq, SingleXChainSingleVaultWithdraw, SingleXChainMultiVaultWithdraw, MultiXChainSingleVaultWithdraw, MultiXChainMultiVaultWithdraw} from "types/Lib.sol";
import {MetaVault} from "src/MetaVault.sol";
import {Script, console2} from "forge-std/Script.sol";
import {ProxyAdmin} from "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import {USDCE_BASE, SUPERFORM_SUPERPOSITIONS_BASE, SUPERFORM_ROUTER_BASE} from "src/helpers/AddressBook.sol";
import {ISuperPositions, IMetaVault} from "interfaces/Lib.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC7540Engine} from "src/modules/Lib.sol";
import {LibString} from "solady/utils/LibString.sol";

contract DeploymentScript is Script {
    IMetaVault public vault;
    address public vaultAdmin;
    address user = 0x429796dAc057E7C15724196367007F1e9Cff82F9;
    uint256 constant superformId =
        859962937750378607403547653689780213346472919703413156121052;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        vault = IMetaVault(0xc9a42fEB7ba832C806F1fe47F2fFd73837CE3c21);
        uint256 assets = 8998921; // 1 USDC

        //console2.log("data", LibString.toHexString(data));
        ERC7540Engine.ProcessRedeemRequestCache memory cachedRoute = vault
            .previewWithdrawalRoute(assets);
        console2.log("cachedRoute", cachedRoute.amountToWithdraw);
        console2.log("cachedRoute", cachedRoute.isSingleChain);
        console2.log("dstVaults", cachedRoute.dstVaults[1][0]);

        ERC7540Engine.ProcessRedeemRequestConfig memory config;
        config.shares = 1000000;
        config.controller = user;
        config.owner = user;
        SingleXChainSingleVaultWithdraw memory sXsV;
        SingleXChainMultiVaultWithdraw memory sXmV;
        MultiXChainSingleVaultWithdraw memory mXsV;
        MultiXChainMultiVaultWithdraw memory mXmV;

        vault.processRedeemRequest(user, sXsV, sXmV, mXsV, mXmV);
    }
}
