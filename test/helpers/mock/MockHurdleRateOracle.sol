// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract MockHurdleRateOracle {
    function getAssetRate(address asset) external view returns (uint256) {
        return 600;
    }
}
