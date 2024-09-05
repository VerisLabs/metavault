/// SPDX-License-Identifer: MIT
pragma solidity 0.8.21;

import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { ERC7540_Request, ERC7540_FilledRequest, ERC7540Lib } from "../types/Lib.sol";

/// @notice Simple ERC7540 async Tokenized Vault implementation
/// @author Solthodox (https://github.com/Solthodox)
abstract contract ERC7540 is ERC4626 {
    using SafeTransferLib for address;
    using ERC7540Lib for ERC7540_Request;
    using ERC7540Lib for ERC7540_FilledRequest;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Emitted when `assets` tokens are deposited into the vault
    event DepositRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address source, uint256 assets
    );

    /// @dev Emitted when `shares` vault shares are redeemed
    event RedeemRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address source, uint256 shares
    );

    /// @dev Emitted when `controller` gives allowance to `operator`
    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    /// @dev `keccak256(bytes("DepositRequest(address,address,uint256,address,uint256)"))`.
    uint256 private constant _DEPOSIT_REQUEST_EVENT_SIGNATURE =
        0xbb58420bb8ce44e11b84e214cc0de10ce5e7c24d0355b2815c3d758b514cae72;

    /// @dev `keccak256(bytes("RedeemRequest(address,address,uint256,address,uint256)"))`.
    uint256 private constant _REDEEM_REQUEST_EVENT_SIGNATURE =
        0x1fdc681a13d8c5da54e301c7ce6542dcde4581e4725043fdab2db12ddc574506;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Saves the ERC7540 deposit requests when calling `requestDeposit`
    mapping(address => ERC7540_Request) private _pendingDepositRequest;

    /// @notice Saves the ERC7540 redeem requests when calling `requestRedeem`
    mapping(address => ERC7540_Request) private _pendingRedeemRequest;

    /// @notice Saves the result of the deposit after the request has been processed
    mapping(address => ERC7540_FilledRequest) private _claimableDepositRequest;

    /// @notice Saves the result of the redeem after the request has been processed
    mapping(address => ERC7540_FilledRequest) private _claimableRedeemRequest;

    /// @notice ERC7540 operator approvals
    mapping(address controller => mapping(address operator => bool)) private isOperator;

    /// @dev Preview functions for ERC-7540 vaults revert
    function previewDeposit(uint256 assets) public pure override returns (uint256 shares) {
        assets; // silence compiler warnings
        shares; // silence compiler warnings
        revert();
    }

    /// @dev Preview functions for ERC-7540 vaults revert
    function previewMint(uint256 shares) public pure override returns (uint256 assets) {
        shares; // silence compiler warnings
        assets; // silence compiler warnings
        revert();
    }

    /// @dev Preview functions for ERC-7540 vaults revert
    function previewWithdraw(uint256 assets) public pure override returns (uint256 shares) {
        assets; // silence compiler warnings
        shares; // silence compiler warnings
        revert();
    }

    /// @dev Preview functions for ERC-7540 vaults revert
    function previewRedeem(uint256 shares) public pure override returns (uint256 assets) {
        shares; // silence compiler warnings
        assets; // silence compiler warnings
        revert();
    }

    /// @dev The deposit amount is limited by the claimable deposit requests of the user
    function maxDeposit(address to) public view virtual override returns (uint256 assets) {
        return _claimableDepositRequest[to].assets;
    }

    /// @dev The mint amount is limited by the claimable deposit requests of the user
    function maxMint(address to) public view virtual override returns (uint256 shares) {
        return convertToShares(maxDeposit(to));
    }

    /// @dev The withdraw amount is limited by the claimable redeem requests of the user
    function maxWithdraw(address owner) public view virtual override returns (uint256 assets) {
        return convertToAssets(maxRedeem(owner));
    }

    /// @dev The redeem amount is limited by the claimable redeem requests of the user
    function maxRedeem(address owner) public view virtual override returns (uint256 shares) {
        return _claimableDepositRequest[owner].shares;
    }

    /// @dev Transfers assets from sender into the Vault and submits a Request for asynchronous deposit.
    ///
    /// - MUST support ERC-20 approve / transferFrom on asset as a deposit Request flow.
    /// - MUST revert if all of assets cannot be requested for deposit.
    /// - owner MUST be msg.sender unless some unspecified explicit approval is given by the caller,
    ///    approval of ERC-20 tokens from owner to sender is NOT enough.
    ///
    /// @param assets the amount of deposit assets to transfer from owner
    /// @param controller the controller of the request who will be able to operate the request
    /// @param owner the source of the deposit assets
    ///
    /// NOTE: most implementations will require pre-approval of the Vault with the Vault's underlying asset token.
    function requestDeposit(
        uint256 assets,
        address controller,
        address owner
    )
        public
        virtual
        returns (uint256 requestId)
    {
        if (assets == 0) revert();
        requestId = _requestDeposit(assets, controller, owner, msg.sender);
        // TODO: event emission in assembly
    }

    /// @dev Assumes control of shares from sender into the Vault and submits a Request for asynchronous redeem.
    ///
    /// - MUST support a redeem Request flow where the control of shares is taken from sender directly
    ///   where msg.sender has ERC-20 approval over the shares of owner.
    /// - MUST revert if all of shares cannot be requested for redeem.
    ///
    /// @param shares the amount of shares to be redeemed to transfer from owner
    /// @param controller the controller of the request who will be able to operate the request
    /// @param owner the source of the shares to be redeemed
    ///
    /// NOTE: most implementations will require pre-approval of the Vault with the Vault's share token.
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    )
        public
        virtual
        returns (uint256 requestId)
    {
        if (shares == 0) revert();
        // If msg.sender is operator of owner, the transfer is executed as if
        // the sender is the owner, to bypass the allowance check
        address sender = isOperator[owner][msg.sender] ? owner : msg.sender;
        return _requestRedeem(shares, controller, owner, sender);
    }

    /// @dev Mints shares Vault shares to receiver by claiming the Request of the controller.
    ///
    /// - MUST emit the Deposit event.
    /// - controller MUST equal msg.sender unless the controller has approved the msg.sender as an operator.
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256 shares) {
        return deposit(assets, receiver, msg.sender);
    }

    /// @dev Mints shares Vault shares to receiver by claiming the Request of the controller.
    ///
    /// - MUST emit the Deposit event.
    /// - controller MUST equal msg.sender unless the controller has approved the msg.sender as an operator.
    function deposit(uint256 assets, address receiver, address controller) public virtual returns (uint256 shares) {
        _validateController(controller);
        if (assets > maxDeposit(controller)) revert DepositMoreThanMax();
        return _deposit(assets, receiver, controller);
    }


    /// @dev Mints exactly shares Vault shares to receiver by claiming the Request of the controller.
    ///
    /// - MUST emit the Deposit event.
    /// - controller MUST equal msg.sender unless the controller has approved the msg.sender as an operator.
    function mint(uint256 shares, address receiver) public virtual override returns (uint256 assets) {
        return mint(shares, receiver, msg.sender);
    }

    /// @dev Mints exactly shares Vault shares to receiver by claiming the Request of the controller.
    ///
    /// - MUST emit the Deposit event.
    /// - controller MUST equal msg.sender unless the controller has approved the msg.sender as an operator.
    function mint(uint256 shares, address receiver, address controller) public virtual returns (uint256 assets) {
        if (shares > maxMint(controller)) revert MintMoreThanMax();
        _validateController(controller);
        return _mint(shares, receiver, controller);
    }

    function redeem(uint256 shares, address to, address controller) public virtual override returns (uint256 assets) {
        if (shares > maxRedeem(controller)) revert RedeemMoreThanMax();
        _validateController(controller);
        return _redeem(shares, to, controller);
    }

    function withdraw(
        uint256 assets,
        address to,
        address controller
    )
        public
        virtual
        override
        returns (uint256 shares)
    {
        if (shares > maxWithdraw(controller)) revert WithdrawMoreThanMax();
        _validateController(controller);
        return _withdraw(assets, to, controller);
    }

    function _deposit(uint256 assets, address receiver, address controller) internal virtual returns (uint256 shares) {
        ERC7540_FilledRequest memory claimable = _claimableDepositRequest[controller];
        shares = claimable.convertToShares(assets);
        unchecked {
            _claimableDepositRequest[controller].assets -= assets;
            _claimableDepositRequest[controller].shares -= shares;
        }
        _mint(receiver, shares);
    }

    function _mint(uint256 shares, address receiver, address controller) internal virtual returns (uint256 assets) {
        ERC7540_FilledRequest memory claimable = _claimableDepositRequest[controller];
        assets = claimable.convertToAssetsUp(shares);
        unchecked {
            _claimableDepositRequest[controller].assets -= assets;
            _claimableDepositRequest[controller].shares -= shares;
        }
        _mint(receiver, shares);
    }

    function _redeem(uint256 shares, address receiver, address controller) internal virtual returns (uint256 assets) { }

    function _withdraw(
        uint256 assets,
        address receiver,
        address controller
    )
        internal
        virtual
        returns (uint256 shares)
    { }

    function _requestDeposit(
        uint256 assets,
        address controller,
        address owner,
        address source
    )
        internal
        virtual
        returns (uint256 requestId)
    {
        source;
        asset().safeTransferFrom(owner, address(this), assets);
        _pendingDepositRequest[controller] = _pendingDepositRequest[controller].add(assets);
        emit DepositRequest(controller, owner, requestId, source, assets);
        return 0;
    }

    function _requestRedeem(
        uint256 shares,
        address controller,
        address owner,
        address source
    )
        internal
        virtual
        returns (uint256 requestId)
    {
        source;
        _burn(owner, shares);
        _pendingRedeemRequest[controller] = _pendingRedeemRequest[controller].add(shares);
        emit RedeemRequest(controller, owner, requestId, source, shares);
        return 0;
    }

    /// @dev Sets or removes an operator for the caller.
    ///
    /// @param operator The address of the operator.
    /// @param approved The approval status.
    /// @return success Whether the call was executed successfully or not
    function setOperator(address operator, bool approved) public returns (bool success) {
        if (msg.sender == operator) revert();
        isOperator[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        return true;
    }

    /// @dev Performs operator and controller permission checks
    function _validateController(address controller) private view {
        if (msg.sender != controller && !isOperator[msg.sender][controller]) revert();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     HOOKS TO OVERRIDE                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Hook that is called when processing a deposit request and make it claimable.
    function _fulfillDepositRequest(
        address controller,
        uint256 assetsFulfilled,
        uint256 sharesMinted
    )
        internal
        virtual
    {
        _pendingDepositRequest[controller] = _pendingDepositRequest[controller].sub(assetsFulfilled);
        _claimableDepositRequest[controller].assets += assetsFulfilled;
        _claimableDepositRequest[controller].shares += sharesMinted;

    }

    /// @dev Hook that is called when processing a redeem request and make it claimable.
    function _fulfillRedeemRequest(
        address controller,
        uint256 sharesFulfilled,
        uint256 assetsWithdrawn
    )
        internal
        virtual
    {
        _pendingRedeemRequest[controller] = _pendingRedeemRequest[controller].sub(sharesFulfilled);
        _claimableRedeemRequest[controller].assets += assetsWithdrawn;
        _claimableRedeemRequest[controller].shares += sharesFulfilled;
    }
}
