/// SPDX-License-Identifer: MIT
pragma solidity ^0.8.19;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

contract ERC20Receiver {
    using SafeTransferLib for address;

    address immutable _deployer;
    address immutable _asset;
    address public owner;
    bytes public key;

    constructor(address _asset_) {
        _asset = _asset_;
        _deployer = msg.sender;
    }

    function balance() external view returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function pull(uint256 amount) external {
        _asset.safeTransfer(_deployer, amount);
    }

    function initialize(address _owner, bytes memory _key) external {
        owner = _owner;
        key = _key;
    }
}
