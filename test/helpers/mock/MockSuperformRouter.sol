import { IBaseRouter, IMetaVault, ISharePriceOracle, ISuperPositions } from "interfaces/Lib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import {
    MultiDstMultiVaultStateReq,
    MultiDstSingleVaultStateReq,
    MultiVaultSFData,
    SingleDirectMultiVaultStateReq,
    SingleDirectSingleVaultStateReq,
    SingleVaultSFData,
    SingleXChainMultiVaultStateReq,
    SingleXChainSingleVaultStateReq,
    VaultData,
    VaultLib
} from "types/Lib.sol";

contract MockSuperformRouter is IBaseRouter {
    using SafeTransferLib for address;
    using VaultLib for VaultData;

    IMetaVault metavault;
    ISuperPositions sp;
    address spReceiver;
    address asset;

    function initialize(IMetaVault _metavault, ISuperPositions _sp, address _asset, address _spReceiver) public {
        asset = _asset;
        sp = _sp;
        metavault = _metavault;
        spReceiver = _spReceiver;
    }

    function singleDirectSingleVaultDeposit(SingleDirectSingleVaultStateReq memory req_) external payable {
        uint256 superformId = req_.superformData.superformId;
        uint256 assets = req_.superformData.amount;
        asset.safeTransferFrom(msg.sender, address(this), assets);
        VaultData memory vault = metavault.getVault(superformId);
        uint256 shares = vault.convertToShares(assets, asset, false) + 1;
        sp.mintSingle(spReceiver, superformId, shares);
    }

    function singleXChainSingleVaultDeposit(SingleXChainSingleVaultStateReq memory req_) external payable {
        uint256 superformId = req_.superformData.superformId;
        uint256 assets = req_.superformData.amount;
        asset.safeTransferFrom(msg.sender, address(this), assets);
        VaultData memory vault = metavault.getVault(superformId);
        uint256 shares = vault.convertToShares(assets, asset, false) + 1;
        sp.mintSingle(spReceiver, superformId, shares);
    }

    function singleDirectMultiVaultDeposit(SingleDirectMultiVaultStateReq memory req_) external payable {
        for (uint256 i = 0; i < req_.superformData.superformIds.length; i++) {
            uint256 superformId = req_.superformData.superformIds[i];
            uint256 assets = req_.superformData.amounts[i];
            asset.safeTransferFrom(msg.sender, address(this), assets);
            VaultData memory vault = metavault.getVault(superformId);
            uint256 shares = vault.convertToShares(assets, asset, false) + 1;
            sp.mintSingle(spReceiver, superformId, shares);
        }
    }

    function singleXChainMultiVaultDeposit(SingleXChainMultiVaultStateReq memory req_) external payable {
        for (uint256 i = 0; i < req_.superformsData.superformIds.length; i++) {
            uint256 superformId = req_.superformsData.superformIds[i];
            uint256 assets = req_.superformsData.amounts[i];
            asset.safeTransferFrom(msg.sender, address(this), assets);
            VaultData memory vault = metavault.getVault(superformId);
            uint256 shares = vault.convertToShares(assets, asset, false);
            sp.mintSingle(spReceiver, superformId, shares);
        }
    }

    function multiDstSingleVaultDeposit(MultiDstSingleVaultStateReq calldata req_) external payable {
        for (uint256 i = 0; i < req_.superformsData.length; i++) {
            SingleVaultSFData memory svd = req_.superformsData[i];
            uint256 superformId = svd.superformId;
            uint256 assets = svd.amount;
            asset.safeTransferFrom(msg.sender, address(this), assets);
            VaultData memory vault = metavault.getVault(superformId);
            uint256 shares = vault.convertToShares(assets, asset, false) + 1;
            sp.mintSingle(spReceiver, superformId, shares);
        }
    }

    function multiDstMultiVaultDeposit(MultiDstMultiVaultStateReq calldata req_) external payable {
        for (uint256 i = 0; i < req_.superformsData.length; i++) {
            MultiVaultSFData memory mvd = req_.superformsData[i];
            for (uint256 j = 0; j < mvd.superformIds.length; j++) {
                uint256 superformId = mvd.superformIds[j];
                uint256 assets = mvd.amounts[j];
                asset.safeTransferFrom(msg.sender, address(this), assets);
                VaultData memory vault = metavault.getVault(superformId);
                uint256 shares = vault.convertToShares(assets, asset, false) + 1;
                sp.mintSingle(spReceiver, superformId, shares);
            }
        }
    }

    function singleDirectSingleVaultWithdraw(SingleDirectSingleVaultStateReq memory req_) external payable {
        uint256 superformId = req_.superformData.superformId;
        uint256 shares = req_.superformData.amount;
        sp.burnSingle(msg.sender, superformId, shares);
        VaultData memory vault = metavault.getVault(superformId);
        uint256 assets = vault.convertToAssets(shares, asset, false);
        asset.safeTransfer(msg.sender, assets);
    }

    function singleXChainSingleVaultWithdraw(SingleXChainSingleVaultStateReq memory req_) external payable {
        uint256 superformId = req_.superformData.superformId;
        uint256 shares = req_.superformData.amount;
        sp.burnSingle(msg.sender, superformId, shares);
        VaultData memory vault = metavault.getVault(superformId);
        uint256 assets = vault.convertToAssets(shares, asset, false);
        asset.safeTransfer(msg.sender, assets);
    }

    function singleDirectMultiVaultWithdraw(SingleDirectMultiVaultStateReq memory req_) external payable {
        for (uint256 i = 0; i < req_.superformData.superformIds.length; i++) {
            uint256 superformId = req_.superformData.superformIds[i];
            uint256 shares = req_.superformData.amounts[i];
            sp.burnSingle(msg.sender, superformId, shares);
            VaultData memory vault = metavault.getVault(superformId);
            uint256 assets = vault.convertToAssets(shares, asset, false);
            asset.safeTransfer(msg.sender, assets);
        }
    }

    function singleXChainMultiVaultWithdraw(SingleXChainMultiVaultStateReq memory req_) external payable {
        for (uint256 i = 0; i < req_.superformsData.superformIds.length; i++) {
            uint256 superformId = req_.superformsData.superformIds[i];
            uint256 shares = req_.superformsData.amounts[i];
            sp.burnSingle(msg.sender, superformId, shares);
            VaultData memory vault = metavault.getVault(superformId);
            uint256 assets = vault.convertToAssets(shares, asset, false);
            asset.safeTransfer(msg.sender, assets);
        }
    }

    function multiDstSingleVaultWithdraw(MultiDstSingleVaultStateReq calldata req_) external payable {
        for (uint256 i = 0; i < req_.superformsData.length; i++) {
            SingleVaultSFData memory svd = req_.superformsData[i];
            uint256 superformId = svd.superformId;
            uint256 shares = svd.amount;
            sp.burnSingle(msg.sender, superformId, shares);
            VaultData memory vault = metavault.getVault(superformId);
            uint256 assets = vault.convertToAssets(shares, asset, false);
            asset.safeTransfer(msg.sender, assets);
        }
    }

    function multiDstMultiVaultWithdraw(MultiDstMultiVaultStateReq calldata req_) external payable {
        for (uint256 i = 0; i < req_.superformsData.length; i++) {
            MultiVaultSFData memory mvd = req_.superformsData[i];
            for (uint256 j = 0; j < mvd.superformIds.length; j++) {
                uint256 superformId = mvd.superformIds[j];
                uint256 shares = mvd.amounts[j];
                sp.burnSingle(msg.sender, superformId, shares);
                VaultData memory vault = metavault.getVault(superformId);
                uint256 assets = vault.convertToAssets(shares, asset, false);
                asset.safeTransfer(msg.sender, assets);
            }
        }
    }

    function forwardDustToPaymaster(address token_) external { }
}
