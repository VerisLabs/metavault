/// SPDX-License-Identifer: MIT
pragma solidity 0.8.21;

import { ERC4626, SafeTransferLib } from "solady/tokens/ERC4626.sol";

/// @notice Simple ERC7540 async Tokenized Vault implementation
/// @author Unlockd
abstract contract ERC7540 is ERC4626 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @dev Emitted when `assets` tokens are deposited into the vault
    event DepositRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 assets
    );

    /// @dev Emitted when `shares` vault shares are redeemed
    event RedeemRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 shares
    );
    /// @dev Emitted when `controller` gives allowance to `operator`
    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    // TODO: get correct signatures
    /// @dev `keccak256(bytes("DepositRequest(address,address,uint256,address,uint256)"))`.
    uint256 private constant _DEPOSIT_REQUEST_EVENT_SIGNATURE = 1;

    /// @dev `keccak256(bytes("RedeemRequest(address,address,uint256,address,uint256)"))`.
    uint256 private constant _REDEEM_REQUEST_EVENT_SIGNATURE = 2;
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    mapping(address => uint256) public pendingDepositRequest;
    mapping(address => uint256) public claimableDepositRequest;
    mapping(address => uint256) public pendingRedeemRequest;
    mapping(address => uint256) public claimableRedeemRequest;
    mapping(address controller => mapping(address operator => bool)) public isOperator;

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

    /// @notice
    /// @dev
    /// @notice
    /// @notice
    function requestDeposit(
        uint256 assets,
        address controller,
        address owner
    )
        external
        virtual
        returns (uint256 requestId)
    {
        if (assets == 0) revert();
        return _requestDeposit(assets, controller, owner, msg.sender);
    }

    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    )
        external
        virtual
        returns (uint256 requestId)
    {
        if (shares == 0) revert();
        return _requestRedeem(shares, controller, owner, msg.sender);
    }

    function deposit(uint256 assets, address receiver) public virtual override returns (uint256 shares) {
        return _deposit(assets, receiver, msg.sender);
    }

    function deposit(uint256 assets, address receiver, address controller) public virtual returns (uint256 shares) {
        _validateController(controller);
        return _deposit(assets, receiver, controller);
    }

    function mint(uint256 shares, address receiver) public virtual override returns (uint256 assets) {
        return _mint(shares, receiver, msg.sender);
    }

    function mint(uint256 shares, address receiver, address controller) public virtual returns (uint256 assets) {
        _validateController(controller);
        return _mint(shares, receiver, controller);
    }

    function redeem(uint256 shares, address to, address controller) public virtual override returns (uint256 assets) {
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
        _validateController(controller);
        return _withdraw(assets, to, controller);
    }

    function _deposit(uint256 assets, address receiver, address controller) internal virtual returns (uint256 shares) { }

    function _mint(uint256 shares, address receiver, address controller) internal virtual returns (uint256 assets) { }

    function _redeem(uint256 shares, address receiver, address controller) internal virtual returns (uint256 assets) { }

    function _withdraw(uint256 assets, address receiver, address controller) internal virtual returns (uint256 shares) { }


    function _requestDeposit(
        uint256 assets,
        address controller,
        address owner,
        address sender
    )
        internal
        virtual
        returns (uint256 requestIds)
    { }

    function _requestRedeem(
        uint256 assets,
        address controller,
        address owner,
        address sender
    )
        internal
        virtual
        returns (uint256 requestIds)
    { }

    function setOperator(address operator, bool approved) public returns (bool success) {
        if (msg.sender == operator) revert();
        isOperator[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        return true;
    }

    function _validateController(address controller) private view {
        if (msg.sender != controller && !isOperator[msg.sender][controller]) revert();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     HOOKS TO OVERRIDE                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Hook that is called when processing a deposit request and make it claimable.
    function _fulfillDepositRequest(
        uint256 requestId,
        address controller,
        uint256 assetsFulfilled,
        uint256 sharesMinted
    )
        internal
        virtual
    { }

    /// @dev Hook that is called when processing a redeem request and make it claimable.
    function _fulfillRedeemRequest(
        uint256 requestId,
        address controllerm,
        uint256 sharesFulfilled,
        uint256 assetsWithdrawn
    )
        internal
        virtual
    { }
}
