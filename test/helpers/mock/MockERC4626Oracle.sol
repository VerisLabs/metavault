// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { VaultReport } from "src/types/Lib.sol";

contract MockERC4626Oracle {
    mapping(uint64 chainId => mapping(address asset => VaultReport)) public reports;

    function getLatestSharePrice(uint64 chainId, address vaultAddress) public view returns (VaultReport memory) {
        return reports[chainId][vaultAddress];
    }

    function setValues(
        uint64 chainId,
        address vaultAddress,
        uint256 _sharePrice,
        uint256 _lastUpdated,
        address _reporter
    )
        public
    {
        reports[chainId][vaultAddress] =
            VaultReport(uint192(_sharePrice), uint64(_lastUpdated), chainId, _reporter, vaultAddress);
    }
}
