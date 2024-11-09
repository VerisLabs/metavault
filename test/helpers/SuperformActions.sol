pragma solidity 0.8.19;

import { _1_USDCE } from "./Tokens.sol";
import { Test } from "forge-std/Test.sol";
import { ERC4626 } from "solady/tokens/ERC4626.sol";

import {
    EXACTLY_USDC_VAULT_ID_OPTIMISM,
    SUPERFORM_FACTORY_POLYGON,
    SUPERFORM_ROUTER_POLYGON,
    SUPERFORM_SUPERPOSITIONS_POLYGON
} from "src/helpers/AddressBook.sol";
import {
    IBaseRouter as ISuperformRouter, IERC4626Oracle, ISuperPositions, ISuperformFactory
} from "src/interfaces/Lib.sol";
import { LiqRequest, SingleVaultSFData, SingleXChainSingleVaultStateReq, VaultReport } from "src/types/Lib.sol";

contract SuperformActions is Test {
    // From superform API
    bytes public constant EXACTLY_USDC_VAULT_OPTIMISM_600_USDCE_DEPOSIT_PAYLOAD =
        hex"e5672e2300000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000009000000000000000a00000001738c5f15ab47eb018539c955b3341034a978c9590000000000000000000000000000000000000000000000000000000023efb710000000000000000000000000000000000000000000000000000000002291691c00000000000000000000000000000000000000000000000000000000000000c60000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000086000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005e0b4bfa0000000000000000000000005e0b4bfa0b55932a3587e648c3552a6515ba56b1000000000000000000000000000000000000000000000000000000000000088000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000002791bca1f2de4661ed88a30c99a7a9449aa8417400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000065000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006203a3f7332000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000000000000000000000000560dc0de97464b588ac725aac4e6c371c41d519512af2206dffc840669ce9a8517b0000000000000000000000000000000000000000000000000000000000000140000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003c499c542cef5e3811e1192ce70d8cc03d5c33590000000000000000000000003721b0e122768ceddfb3dec810e64c361177f826000000000000000000000000000000000000000000000000000000002395d996000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000066163726f73730000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d7375706572666f726d2e78797a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000111111125421ca6dc452d289314280a0f8842a65000000000000000000000000111111125421ca6dc452d289314280a0f8842a650000000000000000000000002791bca1f2de4661ed88a30c99a7a9449aa841740000000000000000000000003c499c542cef5e3811e1192ce70d8cc03d5c33590000000000000000000000000000000000000000000000000000000023c3460000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000001e807ed2379000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000002791bca1f2de4661ed88a30c99a7a9449aa841740000000000000000000000003c499c542cef5e3811e1192ce70d8cc03d5c3359000000000000000000000000e37e799d5077682fa0a244d46e5649f71457bd090000000000000000000000001231deb6f5749ef6ce6943a275a1d3e7486f4eae0000000000000000000000000000000000000000000000000000000023c34600000000000000000000000000000000000000000000000000000000002396042d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000008100000000000000000000000000000000000000000000000000000000006302a00000000000000000000000000000000000000000000000000000000023683cc2ee63c1e581eecb5db986c20a8c88d8332e7e252a96715657512791bca1f2de4661ed88a30c99a7a9449aa84174111111125421ca6dc452d289314280a0f8842a65000000000000000000000000000000000000000000000000000000000000002a94d11400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008a8503527a7f0000000000000000000000000000000000000000000000000000000066fbba9f0000000000000000000000000000000000000000000000000000000000000080ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000000000000000000000d00dfeeddeadbeef8932eb23bad9bddb5cf81426f78279a53c6c3b7100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    bytes public constant EXACTLY_USDC_VAULT_OPTIMISM_600_USDCE_WITHDRAW_PAYLOAD =
        hex"67d70a2900000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000009000000000000000a00000001738c5f15ab47eb018539c955b3341034a978c9590000000000000000000000000000000000000000000000000000000022c52c330000000000000000000000000000000000000000000000000000000023c9e7a100000000000000000000000000000000000000000000000000000000000005f100000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005e0b4bfa0b55932a3587e648c3552a6515ba56b10000000000000000000000005e0b4bfa0b55932a3587e648c3552a6515ba56b1000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000002791bca1f2de4661ed88a30c99a7a9449aa841740000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006500000000000000000000000000000000000000000000000000000000000000890000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    uint64[7] public DST_CHAINS = [
        1, // Ethereum Mainnet
        137, // Polygon
        56, // Bnb
        10, // Optimism
        8453, // Base
        42_161, // Arbitrum One
        43_114 // Avalanche
    ];

    mapping(uint64 chainId => uint256 forkId) forks;
    mapping(uint256 superformId => mapping(uint256 amount => bytes payload)) public depositPayloads;
    mapping(uint256 superformId => mapping(uint256 amount => bytes payload)) public withdrawPayloads;
    mapping(uint256 superformId => mapping(uint256 amount => uint256 nativeValue)) public depositValues;
    mapping(uint256 superformId => mapping(uint256 amount => uint256 nativeValue)) public withdrawValues;

    ISuperPositions public superPositions;
    ISuperformRouter public vaultRouter;
    ISuperformFactory public factory;

    function setUp() public virtual {
        depositPayloads[EXACTLY_USDC_VAULT_ID_OPTIMISM][600 * _1_USDCE] =
            EXACTLY_USDC_VAULT_OPTIMISM_600_USDCE_DEPOSIT_PAYLOAD;
        withdrawPayloads[EXACTLY_USDC_VAULT_ID_OPTIMISM][600 * _1_USDCE] =
            EXACTLY_USDC_VAULT_OPTIMISM_600_USDCE_WITHDRAW_PAYLOAD;
        depositValues[EXACTLY_USDC_VAULT_ID_OPTIMISM][600 * _1_USDCE] = 1.17187818064546536 ether;
        withdrawValues[EXACTLY_USDC_VAULT_ID_OPTIMISM][600 * _1_USDCE] = 4.332818289827537291 ether;

        superPositions = ISuperPositions(SUPERFORM_SUPERPOSITIONS_POLYGON);
        vaultRouter = ISuperformRouter(SUPERFORM_ROUTER_POLYGON);
        factory = ISuperformFactory(SUPERFORM_FACTORY_POLYGON);

        forks[DST_CHAINS[0]] = vm.createFork(vm.envString("RPC_MAINNET"), 20_819_300);
        forks[DST_CHAINS[1]] = vm.createFork(vm.envString("RPC_POLYGON"), 62_334_140);
        forks[DST_CHAINS[2]] = vm.createFork(vm.envString("RPC_POLYGON"), 1);
        forks[DST_CHAINS[3]] = vm.createFork(vm.envString("RPC_OPTIMISM"), 125_784_213);
        forks[DST_CHAINS[4]] = vm.createFork(vm.envString("RPC_BASE"), 1);
        forks[DST_CHAINS[5]] = vm.createFork(vm.envString("RPC_ARBITRUM"), 1);
        forks[DST_CHAINS[6]] = vm.createFork(vm.envString("RPC_ARBITRUM"), 1);
    }

    function _mintSuperpositions(address to, uint256 superformId, uint256 amount) internal {
        vm.startPrank(address(vaultRouter));
        superPositions.mintSingle(to, superformId, amount);
        vm.stopPrank();
    }

    function _previewDeposit(uint64 chainId, address vault, uint256 assets) internal returns (uint256 shares) {
        uint256 _tempCurrentFork = vm.activeFork();
        vm.selectFork(forks[chainId]);
        shares = ERC4626(vault).previewDeposit(assets);
        vm.selectFork(_tempCurrentFork);
        return shares;
    }

    function _previewRedeem(uint64 chainId, address vault, uint256 shares) internal returns (uint256) {
        uint256 _tempCurrentFork = vm.activeFork();
        vm.selectFork(forks[chainId]);
        shares = ERC4626(vault).previewRedeem(shares);
        vm.selectFork(_tempCurrentFork);
        return shares;
    }

    function _getSharePrice(uint64 chainId, address _vault) internal returns (uint256 sharePrice) {
        uint256 _tempCurrentFork = vm.activeFork();
        vm.selectFork(forks[chainId]);
        ERC4626 vault = ERC4626(_vault);
        sharePrice = vault.convertToAssets(10 ** vault.decimals());
        vm.selectFork(_tempCurrentFork);
        return sharePrice;
    }

    function _getDecimals(uint64 chainId, address vault) internal returns (uint8 decimals) {
        uint256 _tempCurrentFork = vm.activeFork();
        vm.selectFork(forks[chainId]);
        decimals = ERC4626(vault).decimals();
        vm.selectFork(_tempCurrentFork);
        return decimals;
    }

    function _buildInvestSingleXChainSingleVaultParams(
        uint256 _superformId,
        uint256 _amount
    )
        internal
        view
        returns (SingleXChainSingleVaultStateReq memory req)
    {
        bytes memory payload = depositPayloads[_superformId][_amount];
        return _decodeSingleXChainSingleVaultStateReq(payload);
    }

    function _buildWithdrawSingleXChainSingleVaultParams(
        uint256 _superformId,
        uint256 _amount
    )
        public
        view
        returns (
            uint8[] memory ambIds,
            uint256 outputAmount,
            uint256 maxSlippage,
            LiqRequest memory liqRequest,
            bool hasDstSwap
        )
    {
        bytes memory payload = withdrawPayloads[_superformId][_amount];
        SingleXChainSingleVaultStateReq memory req = _decodeSingleXChainSingleVaultStateReq(payload);
        (ambIds, outputAmount, maxSlippage, liqRequest, hasDstSwap) = (
            req.ambIds,
            req.superformData.outputAmount,
            req.superformData.maxSlippage,
            req.superformData.liqRequest,
            req.superformData.hasDstSwap
        );
    }

    function _getInvestSingleXChainSingleVaultValue(
        uint256 _superformId,
        uint256 _amount
    )
        internal
        view
        returns (uint256 value)
    {
        return depositValues[_superformId][_amount];
    }

    function _getWithdrawSingleXChainSingleVaultValue(
        uint256 _superformId,
        uint256 _amount
    )
        internal
        view
        returns (uint256 value)
    {
        return withdrawValues[_superformId][_amount];
    }

    function _decodeSingleXChainSingleVaultStateReq(bytes memory payload)
        private
        pure
        returns (SingleXChainSingleVaultStateReq memory req)
    {
        req = abi.decode(slice(payload, 4, payload.length - 4), (SingleXChainSingleVaultStateReq));
        return req;
    }

    function getSelector(bytes memory _data) private pure returns (bytes4 sig) {
        assembly {
            sig := mload(add(_data, 32))
        }
    }

    function slice(bytes memory _bytes, uint256 _start, uint256 _length) private pure returns (bytes memory) {
        require(_bytes.length >= (_start + _length));

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
            case 0 {
                // Get a location of some free memory and store it in tempBytes as
                // Solidity does for memory variables.
                tempBytes := mload(0x40)

                // The first word of the slice result is potentially a partial
                // word read from the original array. To read it, we calculate
                // the length of that partial word and start copying that many
                // bytes into the array. The first word we copy will start with
                // data we don't care about, but the last `lengthmod` bytes will
                // land at the beginning of the contents of the new array. When
                // we're done copying, we overwrite the full first word with
                // the actual length of the slice.
                let lengthmod := and(_length, 31)

                // The multiplication in the next line is necessary
                // because when slicing multiples of 32 bytes (lengthmod == 0)
                // the following copy loop was copying the origin's length
                // and then ending prematurely not copying everything it should.
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, _length)

                for {
                    // The multiplication in the next line has the same exact purpose
                    // as the one above.
                    let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } { mstore(mc, mload(cc)) }

                mstore(tempBytes, _length)

                //update free-memory pointer
                //allocating the array padded to 32 bytes like the compiler does now
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            //if we want a zero-length slice let's just return a zero-length array
            default {
                tempBytes := mload(0x40)

                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }
}
