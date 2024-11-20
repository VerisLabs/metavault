// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract MockERC4626Oracle {
    mapping(address asset => uint256 price) public sharePrice;
    mapping(address asset => uint256 timestamp) public lastUpdated;

    function getSharePrice(address vaultAddress) public view returns (uint256 price, uint256 lastUpdate) {
        return (sharePrice[vaultAddress], lastUpdated[vaultAddress]);
    }

    function setValues(address vaultAddress, uint256 _sharePrice, uint256 _lastUpdated) public {
        sharePrice[vaultAddress] = _sharePrice;
        lastUpdated[vaultAddress] = _lastUpdated;
    }
}
