//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script, console2 } from "forge-std/Script.sol";
import { IMetaVault } from "interfaces/Lib.sol";
import {
    LiqRequest,
    MultiXChainMultiVaultWithdraw,
    MultiXChainSingleVaultWithdraw,
    ProcessRedeemRequestParams,
    SingleXChainMultiVaultWithdraw,
    SingleXChainSingleVaultWithdraw
} from "types/Lib.sol";

contract TestProcessRedeem is Script {
    IMetaVault public metavault;

    /*
    {"controller":"0x88190A6F759CF1115e0c6BCF4Eea1Fef0994e873","shares":"18000000","sXsV":{"ambIds":[],"outputAmount":"0","maxSlippage":"0","liqRequest":{"txData":"0x","token":"0x0000000000000000000000000000000000000000","interimToken":"0x0000000000000000000000000000000000000000","bridgeId":0,"liqDstChainId":"0","nativeAmount":"0"},"hasDstSwap":false,"value":"0"},"sXmV":{"ambIds":[],"outputAmounts":[],"maxSlippages":[],"liqRequests":[],"hasDstSwaps":[],"value":"0"},"mXsV":{"ambIds":[],"outputAmounts":[],"maxSlippages":[],"liqRequests":[],"hasDstSwaps":[],"value":"0"},"mXmV":{"ambIds":[[5,9],[5,9]],"value":"400482703759229","outputAmounts":["1","1"],"maxSlippages":[["1521"],["1521","1521"]],"liqRequests":[[{"txData":"0x","token":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","interimToken":"0x0000000000000000000000000000000000000000","bridgeId":101,"liqDstChainId":"8453","nativeAmount":"0"}],[{"txData":"0x","token":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","interimToken":"0x0000000000000000000000000000000000000000","bridgeId":101,"liqDstChainId":"8453","nativeAmount":"0"},{"txData":"0x","token":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","interimToken":"0x0000000000000000000000000000000000000000","bridgeId":101,"liqDstChainId":"8453","nativeAmount":"0"}]],"hasDstSwaps":[[false],[false,false]]}}
    */

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("RELAYER_PRIVATE_KEY");
        address metavaultAddress = vm.envAddress("METAVAULT_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);
        metavault = IMetaVault(metavaultAddress);

        // Setup sXsV (SingleXChainSingleVaultWithdraw)
        uint8[] memory sXsVAmbIds = new uint8[](2);
        sXsVAmbIds[0] = 5; // From the base64 decoded "BQk="
        sXsVAmbIds[1] = 9; // From the base64 decoded "BQo="

        LiqRequest memory sXsVLiqRequest = LiqRequest({
            txData: "",
            token: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            interimToken: address(0),
            bridgeId: 101,
            liqDstChainId: 8453,
            nativeAmount: 0
        });

        SingleXChainSingleVaultWithdraw memory sXsV = SingleXChainSingleVaultWithdraw({
            ambIds: sXsVAmbIds,
            outputAmount: 1,
            maxSlippage: 1521,
            liqRequest: sXsVLiqRequest,
            hasDstSwap: false,
            value: 150_103_667_585_979
        });

        // Setup empty sXmV (SingleXChainMultiVaultWithdraw)
        uint8[] memory emptyUint8Array = new uint8[](0);
        uint256[] memory emptyOutputAmounts = new uint256[](0);
        uint256[] memory emptyMaxSlippages = new uint256[](0);
        LiqRequest[] memory emptyLiqRequests = new LiqRequest[](0);
        bool[] memory emptyHasDstSwaps = new bool[](0);

        SingleXChainMultiVaultWithdraw memory sXmV = SingleXChainMultiVaultWithdraw({
            ambIds: emptyUint8Array,
            outputAmounts: emptyOutputAmounts,
            maxSlippages: emptyMaxSlippages,
            liqRequests: emptyLiqRequests,
            hasDstSwaps: emptyHasDstSwaps,
            value: 0
        });

        // Setup empty mXsV (MultiXChainSingleVaultWithdraw)
        uint8[][] memory emptyUint8ArrayArray = new uint8[][](0);

        MultiXChainSingleVaultWithdraw memory mXsV = MultiXChainSingleVaultWithdraw({
            ambIds: emptyUint8ArrayArray,
            outputAmounts: emptyOutputAmounts,
            maxSlippages: emptyMaxSlippages,
            liqRequests: emptyLiqRequests,
            hasDstSwaps: emptyHasDstSwaps,
            value: 0
        });

        // Setup empty mXmV (MultiXChainMultiVaultWithdraw)
        uint256[][] memory emptyOutputAmountsArray = new uint256[][](0);
        uint256[][] memory emptyMaxSlippagesArray = new uint256[][](0);
        LiqRequest[][] memory emptyLiqRequestsArray = new LiqRequest[][](0);
        bool[][] memory emptyHasDstSwapsArray = new bool[][](0);

        MultiXChainMultiVaultWithdraw memory mXmV = MultiXChainMultiVaultWithdraw({
            ambIds: emptyUint8ArrayArray,
            outputAmounts: emptyOutputAmountsArray,
            maxSlippages: emptyMaxSlippagesArray,
            liqRequests: emptyLiqRequestsArray,
            hasDstSwaps: emptyHasDstSwapsArray,
            value: 0
        });

        // Call processRedeemRequest
        metavault.processRedeemRequest{ value: 150_103_667_585_979 }(
            ProcessRedeemRequestParams({
                controller: 0x429796dAc057E7C15724196367007F1e9Cff82F9,
                shares: 0,
                sXsV: sXsV,
                sXmV: sXmV,
                mXsV: mXsV,
                mXmV: mXmV
            })
        );

        vm.stopBroadcast();
    }
}
