contract MaxApyCrossChainVaultEvents {
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

    /// @dev Emitted during a mint call or deposit call.
    event Deposit(address indexed by, address indexed owner, uint256 assets, uint256 shares);

    /// @dev Emitted during a withdraw call or redeem call.
    event Withdraw(address indexed by, address indexed to, address indexed owner, uint256 assets, uint256 shares);
}
