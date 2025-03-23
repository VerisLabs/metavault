// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { AddressSet, LibAddressSet } from "./AddressSet.sol";
import { MockERC4626 } from "./mock/MockERC4626.sol";
import { MockERC4626Oracle } from "./mock/MockERC4626Oracle.sol";
import { LibPRNG } from "solady/utils/LibPRNG.sol";

struct VaultInfo {
    uint256 superformId;
    uint64 chainId;
    address vault;
}

struct VaultSet {
    VaultInfo[] vaults;
    mapping(address => bool) saved;
    mapping(address => uint256) index;
}

abstract contract Vaults {
    using LibVaultSet for VaultSet;
    using LibPRNG for LibPRNG.PRNG;
    using LibPRNG for LibPRNG.LazyShuffler;

    uint256 public constant N_CHAINS = 7;
    uint64[N_CHAINS] public DST_CHAINS = [
        1, // Ethereum Mainnet
        137, // Polygon
        56, // BNB Chain
        10, // Optimism
        8453, // Base
        42_161, // Arbitrum One
        43_114 // Avalanche
    ];

    ////////////////////////////////////////////////////////////////
    ///                      VAULTS CONFIG                         ///
    ////////////////////////////////////////////////////////////////
    VaultSet internal _vaults;
    VaultInfo internal currentVault;
    LibPRNG.LazyShuffler internal shuffler;

    uint64 constant THIS_CHAIN = 1; // Assuming chain 1 is "this" chain

    modifier createVault(address token, MockERC4626Oracle oracle) {
        // Generate random superformId and chainId that don't already exist
        uint256 superformId;
        uint64 chainId;
        bool exists;

        if (!shuffler.initialized()) {
            shuffler.initialize(20_000);
        }

        superformId = shuffler.next(block.timestamp);
        chainId = uint64(DST_CHAINS[shuffler.next(block.timestamp) % N_CHAINS]);

        address vault = _vaults.addWithMock(superformId, chainId, token, oracle, shuffler);
        currentVault = _vaults.getInfo(vault);
        _;
    }

    modifier useVault(uint256 vaultIndexSeed) {
        address vault = _vaults.rand(vaultIndexSeed);
        if (vault == address(0)) return;
        currentVault = _vaults.getInfo(vault);
        _;
    }
}

library LibVaultSet {
    using LibPRNG for LibPRNG.LazyShuffler;

    uint64 constant THIS_CHAIN = 1; // Assuming chain 1 is "this" chain

    function add(VaultSet storage s, uint256 superformId, uint64 chainId, address vault) internal {
        if (!s.saved[vault]) {
            uint256 i = count(s);
            s.vaults.push(VaultInfo({ superformId: superformId, chainId: chainId, vault: vault }));
            s.saved[vault] = true;
            s.index[vault] = i;
        }
    }

    function addWithMock(
        VaultSet storage s,
        uint256 superformId,
        uint64 chainId,
        address asset,
        MockERC4626Oracle oracle,
        LibPRNG.LazyShuffler storage shuffler
    )
        internal
        returns (address)
    {
        address vault;
        if (chainId == THIS_CHAIN) {
            // Deploy mock ERC4626 for local vaults
            MockERC4626 mockVault = new MockERC4626(asset, "Mock Vault", "mVLT", false, 0);
            vault = address(mockVault);

            // Set random share price between 0.8 and 1.5
            uint256 randomNum = shuffler.next(block.timestamp) % 700 + 800; // 800-1500
            uint256 sharePrice = (randomNum * 6) / 1000; // Scale to 6 decimals

            oracle.setValues(uint32(chainId), vault, sharePrice, block.timestamp, asset, address(this), 6);
        } else {
            // For cross-chain, just use a dummy address
            vault = address(uint160(shuffler.next(block.timestamp)));

            // Set random share price between 0.8 and 1.5
            uint256 randomNum = shuffler.next(block.timestamp) % 700 + 800; // 800-1500
            uint256 sharePrice = (randomNum * 6) / 1000; // Scale to 6 decimals
            oracle.setValues(uint32(chainId), vault, sharePrice, block.timestamp, asset, address(this), 6);
        }

        add(s, superformId, chainId, vault);
        return vault;
    }

    function remove(VaultSet storage s, address vault) internal {
        if (!contains(s, vault)) revert();
        uint256 _count = count(s);

        uint256 lastIndex = _count - 1;
        uint256 index = s.index[vault];
        VaultInfo memory temp = s.vaults[lastIndex];

        s.vaults[index] = temp;
        s.vaults[lastIndex] = s.vaults[index];
        s.vaults.pop();

        s.saved[vault] = false;
        s.index[temp.vault] = index;
    }

    function contains(VaultSet storage s, address vault) internal view returns (bool) {
        return s.saved[vault];
    }

    function count(VaultSet storage s) internal view returns (uint256) {
        return s.vaults.length;
    }

    function rand(VaultSet storage s, uint256 seed) internal view returns (address) {
        if (s.vaults.length > 0) {
            return s.vaults[seed % s.vaults.length].vault;
        } else {
            return address(0);
        }
    }

    function getInfo(VaultSet storage s, address vault) internal view returns (VaultInfo memory) {
        if (!contains(s, vault)) revert();
        return s.vaults[s.index[vault]];
    }

    function forEach(VaultSet storage s, function(address) external func) internal {
        for (uint256 i = 0; i < s.vaults.length; i++) {
            func(s.vaults[i].vault);
        }
    }

    function reduce(
        VaultSet storage s,
        uint256 acc,
        function(uint256,address) external returns (uint256) func
    )
        internal
        returns (uint256)
    {
        for (uint256 i = 0; i < s.vaults.length; i++) {
            acc = func(acc, s.vaults[i].vault);
        }
        return acc;
    }
}
