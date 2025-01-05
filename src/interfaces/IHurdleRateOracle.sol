// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IHurdleRateOracle {
    function getAssetRate(address asset) external view returns (uint256);
}
