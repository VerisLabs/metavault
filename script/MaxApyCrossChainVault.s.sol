import {Script} from "forge-std/Script.sol";
import {MaxApyCrossChainVault} from "src/MaxApyCrossChainVault.sol";
import {VaultConfig} from "types/Lib.sol";
import {SUPERFORM_SUPERPOSITIONS_BASE, SUPERFORM_ROUTER_BASE, SUPERFORM_FACTORY_BASE, USDCE_BASE} from "src/helpers/AddressBook.sol";
import {ISuperPositions, IBaseRouter, ISuperformFactory} from "interfaces/Lib.sol";

contract EthereumDeploymentScript is Script {
    MaxApyCrossChainVault vault;
    VaultConfig config;
    address deployerAddress;
    address signerRelayer;
    address relayer;
    address manager;
    address treasury;
    address recoveryAddress;
    address emergencyAdmin;

    function run() public {
        // use another private key here, dont use a keeper account for deployment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");

        // FOR TESTS
        signerRelayer = deployerAddress;
        relayer = deployerAddress;
        manager = deployerAddress;
        treasury = deployerAddress;
        recoveryAddress = deployerAddress;
        emergencyAdmin = deployerAddress;

        bool isFork = vm.envBool("FORK");

        if (isFork) {
            revert("fork setup");
        }

        config = VaultConfig({
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
            treasury: treasury,
            recoveryAddress: recoveryAddress,
            signerRelayer: signerRelayer
        });

        vm.startBroadcast(deployerPrivateKey);

        vault = new MaxApyCrossChainVault(config);

        vault.grantRoles(manager, vault.MANAGER_ROLE());
        vault.grantRoles(relayer, vault.RELAYER_ROLE());
        vault.grantRoles(emergencyAdmin, vault.EMERGENCY_ADMIN_ROLE());
    }
}
