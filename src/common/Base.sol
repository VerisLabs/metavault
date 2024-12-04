import { ISuperformGateway } from "interfaces/Lib.sol";

import { ERC7540, ReentrancyGuard } from "lib/Lib.sol";
import { OwnableRoles } from "solady/auth/OwnableRoles.sol";

import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { VaultData, VaultLib } from "types/Lib.sol";

contract Base is OwnableRoles, ERC7540, ReentrancyGuard {
    using VaultLib for VaultData;

    /// @notice Maximum size of the withdrawal queue
    uint256 public constant WITHDRAWAL_QUEUE_SIZE = 30;

    /// @notice Number of seconds in a year, used for APY calculations
    uint256 public constant SECS_PER_YEAR = 31_556_952;

    /// @notice Maximum basis points (100%)
    uint256 public constant MAX_BPS = 10_000;

    /// @notice Role identifier for admin privileges
    uint256 public constant ADMIN_ROLE = _ROLE_0;

    /// @notice Role identifier for emergency admin privileges
    uint256 public constant EMERGENCY_ADMIN_ROLE = _ROLE_1;

    /// @notice Role identifier for oracle privileges
    uint256 public constant ORACLE_ROLE = _ROLE_2;

    /// @notice Role identifier for manager privileges
    uint256 public constant MANAGER_ROLE = _ROLE_3;

    /// @notice Role identifier for relayer privileges
    uint256 public constant RELAYER_ROLE = _ROLE_4;

    /// @notice Delay period for redeem requests
    uint24 public constant REQUEST_REDEEM_DELAY = 1 days;

    /// @notice Chain ID of the current network
    uint64 public THIS_CHAIN_ID;

    /// @notice Number of supported chains
    uint256 public constant N_CHAINS = 7;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STORAGE                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Cached value of total assets in this vault
    uint128 private _totalIdle;
    /// @notice Cached value of total allocated assets
    uint128 private _totalDebt;
    /// @notice Asset decimals
    uint8 _decimals;
    /// @notice Protocol fee
    uint16 public managementFee;
    /// @notice Protocol fee
    uint16 public performanceFee;
    /// @notice Protocol fee
    uint16 public oracleFee;
    /// @notice Hurdle rate of underlying asset
    uint16 public hurdleRate;
    /// @notice Minimum time users must wait to redeem shares
    uint24 public sharesLockTime;
    /// @notice Delay from processing a redeem till its claimed
    uint24 public processRedeemSettlement;
    /// @notice Wether the vault is paused
    bool public emergencyShutdown;
    /// @notice Fee receiver
    address public treasury;
    /// @notice Underlying asset
    address private immutable _asset;
    /// @notice Gateway contract to interact with superform
    ISuperformGateway public gateway;
    /// @notice ERC20 name
    string private _name;
    /// @notice ERC20 symbol
    string private _symbol;
    /// @notice maps the assets and data of each allocated vault
    /// @notice Vaults portfolio on this same chain
    uint256[WITHDRAWAL_QUEUE_SIZE] public localWithdrawalQueue;
    /// @notice Vaults portfolio in external chains
    uint256[WITHDRAWAL_QUEUE_SIZE] public xChainWithdrawalQueue;
    /// @notice Implementation contract of the receiver contract
    address public receiverImplementation;
    /// @notice Superform recovery address
    address public recoveryAddress;
    /// @notice Timestamp of last report
    uint256 public lastReport;
    /// @notice The ATH share price
    uint256 public sharePriceWaterMark;
    /// @notice Signer address to process redeem requests
    address public signerRelayer;
    /// @notice Array of destination chain IDs
    /// @dev Includes Ethereum Mainnet, Polygon, BNB Chain, Optimism, Base, Arbitrum One, and Avalanche
    uint64[N_CHAINS] public DST_CHAINS = [
        1, // Ethereum Mainnet
        137, // Polygon
        56, // BNB Chain
        10, // Optimism
        8453, // Base
        42_161, // Arbitrum One
        43_114 // Avalanche
    ];
    /// @notice Timestamp of deposit lock
    mapping(address => uint256) private _depositLockCheckPoint;
    /// @notice Storage of each vault related data
    mapping(uint256 => VaultData) public vaults;
    /// @notice the ERC4626 oracle of each chain
    mapping(uint64 chain => address) public oracles;
    /// @notice Timestamp of request redeem lock
    mapping(address => uint256) private _requestRedeemSettlementCheckpoint;
    /// @notice Inverse mapping vault => superformId
    mapping(address => uint256) _vaultToSuperformId;
    /// @notice Redeem is locked when requesting and unlocked when processing
    mapping(address => bool) redeemLocked;
    /// @notice Nonce of each controller
    mapping(address controller => uint256 nonce) private _controllerNonces;
    /// @notice Mapping of chain IDs to their respective indexes
    mapping(uint64 => uint256) chainIndexes;
    /// @notice Mapping of chain method selectors to implementation contracts
    mapping(bytes4 => address) selectorToImplementation;

    /// @dev Private helper to substract a - b or return 0 if it underflows
    function _sub0(uint256 a, uint256 b) private pure returns (uint256) {
        unchecked {
            return a - b > a ? 0 : a - b;
        }
    }

    /// @notice Gets the shares balance of a vault in the portfolio
    /// @param data The vault data structure containing chain ID and address information
    /// @return shares The number of shares held in the vault
    /// @dev For same-chain vaults, fetches directly from the vault; for cross-chain vaults, uses Superform ERC1155
    function _sharesBalance(VaultData memory data) private view returns (uint256 shares) {
        if (data.chainId == THIS_CHAIN_ID) {
            return ERC4626(data.vaultAddress).balanceOf(address(this));
        } else {
            return gateway.balanceOf(address(this), data.superformId);
        }
    }

    /// @dev Private helper to return `x + 1` without the overflow check.
    /// Used for computing the denominator input to `FixedPointMathLib.fullMulDiv(a, b, x + 1)`.
    /// When `x == type(uint).max`, we get `x + 1 == 0` (mod 2**256 - 1),
    /// and `FixedPointMathLib.fullMulDiv` will revert as the denominator is zero.
    function _inc_(uint256 x) private pure returns (uint256) {
        unchecked {
            return x + 1;
        }
    }

    /// @dev Private helper to return if either value is zero.
    function _eitherIsZero_(uint256 a, uint256 b) private pure returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := or(iszero(a), iszero(b))
        }
    }

    /// @dev Private helper get an array uint full of zeros
    /// @param len array length
    /// @return
    function _getEmptyuintArray(uint256 len) private pure returns (uint256[] memory) {
        return new uint256[](len);
    }

    /// @notice Converts a fixed-size array to a dynamic array
    /// @param arr The fixed-size array to convert
    /// @param len The length of the new dynamic array
    /// @return dynArr The converted dynamic array
    /// @dev Used to prepare data for cross-chain transactions
    function _toDynamicUint256Array(
        uint256[WITHDRAWAL_QUEUE_SIZE] memory arr,
        uint256 len
    )
        private
        pure
        returns (uint256[] memory dynArr)
    {
        dynArr = new uint256[](len);
        for (uint256 i = 0; i < len; ++i) {
            dynArr[i] = arr[i];
        }
    }

    /// @dev Helper function to get a empty bools array
    function _getEmptyBoolArray(uint256 len) private pure returns (bool[] memory) {
        return new bool[](len);
    }

    /// @dev Private helper to calculate shares from any @param _totalAssets
    function _convertToShares(uint256 assets, uint256 _totalAssets) private view returns (uint256 shares) {
        if (!_useVirtualShares()) {
            uint256 supply = totalSupply();
            return _eitherIsZero_(assets, supply)
                ? _initialConvertToShares(assets)
                : Math.fullMulDiv(assets, supply, _totalAssets);
        }
        uint256 o = _decimalsOffset();
        if (o == uint256(0)) {
            return Math.fullMulDiv(assets, totalSupply() + 1, _inc_(_totalAssets));
        }
        return Math.fullMulDiv(assets, totalSupply() + 10 ** o, _inc_(_totalAssets));
    }
}
