/// SPDX-License-Identifer: MIT
pragma solidity ^0.8.19;

interface IERC4626Oracle {
    function getSharePrice(address vaultAddress) external view returns (uint256 price, uint256 lastUpdate);
}
