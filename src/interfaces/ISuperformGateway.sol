import { ISuperPositions } from "../interfaces/ISuperPositions.sol";
import {
    MultiDstMultiVaultStateReq,
    MultiDstSingleVaultStateReq,
    MultiVaultSFData,
    SingleDirectMultiVaultStateReq,
    SingleDirectSingleVaultStateReq,
    SingleVaultSFData,
    SingleXChainMultiVaultStateReq,
    SingleXChainSingleVaultStateReq
} from "../types/SuperformTypes.sol";

import { SingleXChainMultiVaultWithdraw, SingleXChainSingleVaultWithdraw } from "../types/VaultTypes.sol";

interface ISuperformGateway {
    function superPositions() external view returns (ISuperPositions);

    function notifyRefund(uint256 superformId, uint256 amount) external;

    function totalpendingXChainInvests() external view returns (uint256);

    function totalPendingXChainWithdraws() external view returns (uint256);

    function totalPendingXChainDivests() external view returns (uint256);

    function balanceOf(address account, uint256 superformId) external view returns (uint256);

    function investSingleXChainSingleVault(SingleXChainSingleVaultStateReq calldata req) external payable;

    function investSingleXChainMultiVault(SingleXChainMultiVaultStateReq calldata req)
        external
        payable
        returns (uint256 totalAmount);

    function investMultiXChainSingleVault(MultiDstSingleVaultStateReq calldata req)
        external
        payable
        returns (uint256 totalAmount);

    function investMultiXChainMultiVault(MultiDstMultiVaultStateReq calldata req)
        external
        payable
        returns (uint256 totalAmount);

    function divestSingleXChainSingleVault(SingleXChainSingleVaultStateReq calldata req)
        external
        payable
        returns (uint256 sharesValue);

    function divestSingleXChainMultiVault(SingleXChainMultiVaultStateReq calldata req)
        external
        payable
        returns (uint256 totalAmount);

    function divestMultiXChainSingleVault(MultiDstSingleVaultStateReq calldata req)
        external
        payable
        returns (uint256 totalAmount);

    function divestMultiXChainMultiVault(MultiDstMultiVaultStateReq calldata req)
        external
        payable
        returns (uint256 totalAmount);

    function liquidateSingleXChainSingleVault(
        uint64 chainId,
        uint256 superformId,
        uint256 amount,
        address receiver,
        SingleXChainSingleVaultWithdraw memory config,
        uint256 totalRequestedAssets
    )
        external
        payable;

    function liquidateSingleXChainMultiVault(
        uint64 chainId,
        uint256[] memory superformIds,
        uint256[] memory amounts,
        address receiver,
        SingleXChainMultiVaultWithdraw memory config,
        uint256 totalRequestedAssets,
        uint256[] memory requestedAssetsPerVault
    )
        external
        payable;

    function liquidateMultiDstSingleVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        SingleVaultSFData[] memory singleVaultDatas,
        uint256[] memory totalRequestedAssets,
        uint256[] memory requestedAssetsPerVault
    )
        external
        payable;

    function liquidateMultiDstMultiVault(
        uint8[][] memory ambIds,
        uint64[] memory dstChainIds,
        MultiVaultSFData[] memory multiVaultDatas,
        uint256[] memory totalRequestedAssets,
        uint256[][] memory requestedAssetsPerVault
    )
        external
        payable;

    function supportsInterface(bytes4 interfaceId) external pure returns (bool isSupported);
    function onERC1155Received(
        address operator,
        address from,
        uint256 superformId,
        uint256 value,
        bytes memory data
    )
        external
        returns (bytes4);

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] memory superformIds,
        uint256[] memory values,
        bytes memory data
    )
        external
        returns (bytes4);

    function getReceiver(address controller, bytes memory key) external returns (address receiverAddress);
}
