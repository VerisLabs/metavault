import {
    MultiDstMultiVaultStateReq,
    MultiDstSingleVaultStateReq,
    SingleDirectMultiVaultStateReq,
    SingleDirectSingleVaultStateReq,
    SingleXChainMultiVaultStateReq,
    SingleXChainSingleVaultStateReq
} from "../types/SuperformTypes.sol";

interface ISuperformGateway {
    function balanceOf(address account, uint256 superformId) external view returns (uint256);

    function totalpendingXChainInvests() external view returns (uint256);

    function totalPendingXChainDivests() external view returns (uint256);

    function totalPendingXChainWithdraws() external view returns (uint256);

    function pendingXChainInvests(uint256) external view returns (uint256);

    function pendingXChainWithdraws(uint256) external view returns (uint256);

    function pendingXChainDivests(uint256) external view returns (uint256);

    function investSingleXChainSingleVault(SingleXChainSingleVaultStateReq calldata req) external payable;

    function investSingleXChainMultiVault(SingleXChainMultiVaultStateReq calldata req) external payable;

    function investMultiXChainSingleVault(MultiDstSingleVaultStateReq calldata req) external payable;

    function investMultiXChainMultiVault(MultiDstMultiVaultStateReq calldata req) external payable;

    function divestSingleXChainSingleVault(SingleXChainSingleVaultStateReq calldata req) external payable;

    function divestSingleXChainMultiVault(SingleXChainMultiVaultStateReq calldata req) external payable;

    function divestMultiXChainSingleVault(MultiDstSingleVaultStateReq calldata req) external payable;

    function divestMultiXChainMultiVault(MultiDstMultiVaultStateReq calldata req) external payable;

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
}
