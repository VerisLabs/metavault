//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    DivestSuperform, InvestSuperform, LiquidateSuperform, SuperformGateway
} from "crosschain/SuperformGateway/Lib.sol";
import { Script, console2 } from "forge-std/Script.sol";

import { SUPERFORM_ROUTER_BASE, SUPERFORM_SUPERPOSITIONS_BASE } from "helpers/AddressBook.sol";
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

contract DeployScript is Script {
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
    address treasury;

    function run() public {
        // Default run function for backward compatibility - get token from env var
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        _deployWithToken(tokenAddress);
    }

    function runWithParams(address tokenAddress) public {
        _deployWithToken(tokenAddress);
    }

    function _deployWithToken(address tokenAddress) internal {
        console2.log("=======================================================");
        console2.log("            STARTING DEPLOYMENT PROCESS");
        console2.log("=======================================================");

        console2.log("Loading environment variables...");
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        hurdleRateOracleAddress = vm.envAddress("HURDLE_RATE_ORACLE_ADDRESS");
        treasury = vm.envAddress("TREASURY_ADDRESS");
        adminAndOwnerRole = vm.envAddress("ADMIN_AND_OWNER_ROLE");
        relayerRole = vm.envAddress("RELAYER_ROLE");
        emergencyAdminRole = vm.envAddress("EMERGENCY_ADMIN_ROLE");
        managerAddressRole = vm.envAddress("MANAGER_ADDRESS_ROLE");

        console2.log("Environment variables loaded successfully");
        console2.log("Deployer account:", vm.addr(deployerPrivateKey));
        console2.log("Hurdle Rate Oracle:", hurdleRateOracleAddress);
        console2.log("Treasury:", treasury);
        console2.log("Admin/Owner Role address:", adminAndOwnerRole);
        console2.log("Relayer Role address:", relayerRole);
        console2.log("Emergency Admin Role address:", emergencyAdminRole);
        console2.log("Manager Role address:", managerAddressRole);
        console2.log("Token address:", tokenAddress);

        console2.log("-------------------------------------------------------");
        console2.log("Starting broadcast from deployer account");
        vm.startBroadcast(deployerPrivateKey);

        // Generate vault name and symbol based on token address
        (string memory vaultName, string memory vaultSymbol) = _generateVaultNameAndSymbol(tokenAddress);

        console2.log("Setting up vault configuration...");
        config = VaultConfig({
            asset: tokenAddress,
            name: vaultName,
            symbol: vaultSymbol,
            managementFee: 100,
            performanceFee: 2000,
            oracleFee: 50,
            hurdleRateOracle: IHurdleRateOracle(hurdleRateOracleAddress),
            sharesLockTime: 0,
            superPositions: ISuperPositions(SUPERFORM_SUPERPOSITIONS_BASE),
            treasury: treasury,
            signerRelayer: relayerRole,
            owner: adminAndOwnerRole
        });
        console2.log("Vault configuration set with:");
        console2.log(" - Asset:", tokenAddress);
        console2.log(" - Name:", vaultName);
        console2.log(" - Symbol:", vaultSymbol);
        console2.log(" - Management Fee: 100 (1%)");
        console2.log(" - Performance Fee: 2000 (20%)");
        console2.log(" - Oracle Fee: 50 (0.5%)");
        console2.log(" - SuperPositions:", address(SUPERFORM_SUPERPOSITIONS_BASE));

        console2.log("-------------------------------------------------------");
        console2.log("Deploying MetaVault contract...");
        MetaVault _vault = new MetaVault(config);
        vault = IMetaVault(address(_vault));
        console2.log("MetaVault deployed successfully at:", address(vault));

        console2.log("-------------------------------------------------------");
        console2.log("Deploying Superform Gateway components...");

        console2.log("1. Deploying InvestSuperform...");
        InvestSuperform invest = new InvestSuperform();
        console2.log("   InvestSuperform deployed at:", address(invest));

        console2.log("2. Deploying DivestSuperform...");
        DivestSuperform divest = new DivestSuperform();
        console2.log("   DivestSuperform deployed at:", address(divest));

        console2.log("3. Deploying LiquidateSuperform...");
        LiquidateSuperform liquidate = new LiquidateSuperform();
        console2.log("   LiquidateSuperform deployed at:", address(liquidate));

        console2.log("4. Deploying SuperformGateway...");
        SuperformGateway _gateway = new SuperformGateway(
            IMetaVault(vault),
            IBaseRouter(SUPERFORM_ROUTER_BASE),
            ISuperPositions(SUPERFORM_SUPERPOSITIONS_BASE),
            adminAndOwnerRole
        );
        gateway = ISuperformGateway(address(_gateway));
        console2.log("   SuperformGateway deployed at:", address(gateway));
        console2.log("   Using Router:", SUPERFORM_ROUTER_BASE);

        console2.log("-------------------------------------------------------");
        console2.log("Adding function selectors to SuperformGateway...");

        console2.log("1. Adding InvestSuperform functions...");
        bytes4[] memory investSelectors = invest.selectors();
        console2.log("   Number of selectors:", investSelectors.length);
        for (uint256 i = 0; i < investSelectors.length; i++) {
            console2.log("   - Selector:", uint32(investSelectors[i]));
        }
        _gateway.addFunctions(investSelectors, address(invest), false);
        console2.log("   InvestSuperform functions added successfully");

        console2.log("2. Adding DivestSuperform functions...");
        bytes4[] memory divestSelectors = divest.selectors();
        console2.log("   Number of selectors:", divestSelectors.length);
        for (uint256 i = 0; i < divestSelectors.length; i++) {
            console2.log("   - Selector:", uint32(divestSelectors[i]));
        }
        _gateway.addFunctions(divestSelectors, address(divest), false);
        console2.log("   DivestSuperform functions added successfully");

        console2.log("3. Adding LiquidateSuperform functions...");
        bytes4[] memory liquidateSelectors = liquidate.selectors();
        console2.log("   Number of selectors:", liquidateSelectors.length);
        for (uint256 i = 0; i < liquidateSelectors.length; i++) {
            console2.log("   - Selector:", uint32(liquidateSelectors[i]));
        }
        _gateway.addFunctions(liquidateSelectors, address(liquidate), false);
        console2.log("   LiquidateSuperform functions added successfully");

        console2.log("-------------------------------------------------------");
        console2.log("Setting gateway in MetaVault...");
        vault.setGateway(address(gateway));
        console2.log("Gateway set successfully in MetaVault");

        console2.log("-------------------------------------------------------");
        console2.log("Deploying and adding vault modules...");

        console2.log("1. Deploying ERC7540Engine...");
        engine = new ERC7540Engine();
        bytes4[] memory engineSelectors = engine.selectors();
        console2.log("   ERC7540Engine deployed at:", address(engine));
        console2.log("   Number of selectors:", engineSelectors.length);
        vault.addFunctions(engineSelectors, address(engine), false);
        console2.log("   ERC7540Engine functions added to vault");

        console2.log("2. Deploying ERC7540EngineReader...");
        engineReader = new ERC7540EngineReader();
        bytes4[] memory engineReaderSelectors = engineReader.selectors();
        console2.log("   ERC7540EngineReader deployed at:", address(engineReader));
        console2.log("   Number of selectors:", engineReaderSelectors.length);
        vault.addFunctions(engineReaderSelectors, address(engineReader), false);
        console2.log("   ERC7540EngineReader functions added to vault");

        console2.log("3. Deploying ERC7540EngineSignatures...");
        engineSignatures = new ERC7540EngineSignatures();
        bytes4[] memory engineSignaturesSelectors = engineSignatures.selectors();
        console2.log("   ERC7540EngineSignatures deployed at:", address(engineSignatures));
        console2.log("   Number of selectors:", engineSignaturesSelectors.length);
        vault.addFunctions(engineSignaturesSelectors, address(engineSignatures), false);
        console2.log("   ERC7540EngineSignatures functions added to vault");

        console2.log("4. Deploying AssetsManager...");
        assetManager = new AssetsManager();
        bytes4[] memory assetManagerSelectors = assetManager.selectors();
        console2.log("   AssetsManager deployed at:", address(assetManager));
        console2.log("   Number of selectors:", assetManagerSelectors.length);
        vault.addFunctions(assetManagerSelectors, address(assetManager), false);
        console2.log("   AssetsManager functions added to vault");

        console2.log("5. Deploying EmergencyAssetsManager...");
        emergencyAssetsManager = new EmergencyAssetsManager();
        bytes4[] memory emergencyAssetsManagerSelectors = emergencyAssetsManager.selectors();
        console2.log("   EmergencyAssetsManager deployed at:", address(emergencyAssetsManager));
        console2.log("   Number of selectors:", emergencyAssetsManagerSelectors.length);
        vault.addFunctions(emergencyAssetsManagerSelectors, address(emergencyAssetsManager), false);
        console2.log("   EmergencyAssetsManager functions added to vault");

        console2.log("6. Deploying MetaVaultReader...");
        metaVaultReader = new MetaVaultReader();
        bytes4[] memory metaVaultReaderSelectors = metaVaultReader.selectors();
        console2.log("   MetaVaultReader deployed at:", address(metaVaultReader));
        console2.log("   Number of selectors:", metaVaultReaderSelectors.length);
        vault.addFunctions(metaVaultReaderSelectors, address(metaVaultReader), false);
        console2.log("   MetaVaultReader functions added to vault");

        console2.log("-------------------------------------------------------");
        console2.log("Setting up roles...");

        console2.log("1. Granting MANAGER_ROLE to:", managerAddressRole);
        vault.grantRoles(managerAddressRole, vault.MANAGER_ROLE());
        console2.log("   MANAGER_ROLE granted successfully");

        console2.log("2. Granting RELAYER_ROLE to:", relayerRole);
        vault.grantRoles(relayerRole, vault.RELAYER_ROLE());
        gateway.grantRoles(relayerRole, gateway.RELAYER_ROLE());
        console2.log("   RELAYER_ROLE granted successfully");

        console2.log("3. Granting EMERGENCY_ADMIN_ROLE to:", emergencyAdminRole);
        vault.grantRoles(emergencyAdminRole, vault.EMERGENCY_ADMIN_ROLE());
        console2.log("   EMERGENCY_ADMIN_ROLE granted successfully");

        console2.log("-------------------------------------------------------");
        console2.log("Setting vault parameters...");

        // Set dust threshold based on token decimals
        uint256 dustThreshold = _getDustThresholdForToken(tokenAddress);
        console2.log("Setting Dust Threshold to:", dustThreshold);
        vault.setDustThreshold(dustThreshold);
        console2.log("Dust Threshold set successfully");

        console2.log("=======================================================");
        console2.log("            DEPLOYMENT SUMMARY");
        console2.log("=======================================================");
        console2.log("Vault deployed at:              ", address(vault));
        console2.log("Gateway deployed at:            ", address(gateway));
        console2.log("Engine deployed at:             ", address(engine));
        console2.log("EngineReader deployed at:       ", address(engineReader));
        console2.log("EngineSignatures deployed at:   ", address(engineSignatures));
        console2.log("AssetManager deployed at:       ", address(assetManager));
        console2.log("EmergencyAssetsManager deployed at: ", address(emergencyAssetsManager));
        console2.log("MetaVaultReader deployed at:    ", address(metaVaultReader));
        console2.log("InvestSuperform deployed at:    ", address(invest));
        console2.log("DivestSuperform deployed at:    ", address(divest));
        console2.log("LiquidateSuperform deployed at: ", address(liquidate));
        console2.log("=======================================================");
        console2.log("            DEPLOYMENT COMPLETE");
        console2.log("=======================================================");

        vm.stopBroadcast();
    }

    // Helper function to generate vault name and symbol based on token address
    function _generateVaultNameAndSymbol(address tokenAddress)
        internal
        view
        returns (string memory name, string memory symbol)
    {
        try IERC20Metadata(tokenAddress).name() returns (string memory tokenName) {
            try IERC20Metadata(tokenAddress).symbol() returns (string memory tokenSymbol) {
                name = string(abi.encodePacked("max", tokenName, " Vault"));
                symbol = string(abi.encodePacked("max", tokenSymbol));
                return (name, symbol);
            } catch {
                // Default if symbol fails
                name = string(abi.encodePacked("max", tokenName, " Vault"));
                symbol = "maxTKN";
                return (name, symbol);
            }
        } catch {
            // Default if both fail
            name = "MetaVault";
            symbol = "maxTKN";
            return (name, symbol);
        }
    }

    // Helper function to get appropriate dust threshold based on token decimals
    function _getDustThresholdForToken(address tokenAddress) internal view returns (uint256) {
        uint8 decimals;
        try IERC20Metadata(tokenAddress).decimals() returns (uint8 tokenDecimals) {
            decimals = tokenDecimals;
        } catch {
            // Default to 18 if decimals() call fails
            decimals = 18;
        }

        // Set dust threshold to equivalent of 3 units with 6 decimals (like USDC)
        // If token has 18 decimals, this would be 3 * 10^18 / 10^6 = 3 * 10^12
        if (decimals >= 6) {
            return 3 * 10 ** (decimals - 6) * 1_000_000;
        } else {
            // For tokens with less than 6 decimals, set a smaller threshold
            return 3 * 10 ** decimals;
        }
    }
}

// Interface needed for token metadata checks
interface IERC20Metadata {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}
