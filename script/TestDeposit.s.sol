//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console2 } from "forge-std/Script.sol";
import { IMetaVault, IERC20 } from "interfaces/Lib.sol";
import { WETH_BASE, USDCE_BASE } from "helpers/AddressBook.sol";

contract TestDepositScript is Script {
   IMetaVault public vault;
   uint256 deployerPrivateKey;
   address deployer;


   function setUp() public {
       // Load environment variables
       deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
       deployer = vm.addr(deployerPrivateKey);
      
       // Load vault address from environment
       address vaultAddress = vm.envAddress("METAVAULT_ADDRESS");
       vault = IMetaVault(vaultAddress);
   }


   function run() public {
       setUp();
      
       console2.log("=======================================================");
       console2.log("            STARTING WETH DEPOSIT TEST");
       console2.log("=======================================================");
      
       console2.log("Deployer address:", deployer);
       console2.log("Vault address:", address(vault));
      
       // Amount to deposit (0.1 WETH)
       uint256 depositAmount = 42_000_000;
      
       console2.log("-------------------------------------------------------");
       console2.log("Starting broadcast from deployer account");
       vm.startBroadcast(deployerPrivateKey);
      
       // Convert ETH to WETH
       //console2.log("Converting ETH to WETH...");
       //IWETH(WETH_BASE).deposit{value: depositAmount}();
      
       // Approve vault to spend WETH
       console2.log("Approving vault to spend WETH...");
       IERC20(USDCE_BASE).approve(address(vault), depositAmount);
      
       // Request deposit
       console2.log("Requesting deposit...");
       uint256 requestId = vault.requestDeposit(depositAmount, deployer, deployer);
       console2.log("Deposit request ID:", requestId);
      
       // Perform deposit
       console2.log("Performing deposit...");
       uint256 shares = vault.deposit(depositAmount, deployer);
       console2.log("Shares received:", shares);
      
       vm.stopBroadcast();
      
       console2.log("=======================================================");
       console2.log("            WETH DEPOSIT TEST COMPLETE");
       console2.log("=======================================================");
       console2.log("Deposit amount:", depositAmount);
       console2.log("Shares received:", shares);
   }
}


interface IWETH {
   function deposit() external payable;
   function approve(address spender, uint256 amount) external returns (bool);
}
