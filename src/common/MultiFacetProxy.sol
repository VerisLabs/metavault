// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Base } from "./Base.sol";
import { Proxy } from "openzeppelin-contracts/proxy/Proxy.sol";

/// @title MultiFacetProxy
/// @notice A proxy contract that can route function calls to different implementation contracts
/// @dev Inherits from Base and OpenZeppelin's Proxy contract
contract MultiFacetProxy is Base, Proxy {
    /// @notice Adds a function selector mapping to an implementation address
    /// @param selector The function selector to add
    /// @param implementation The implementation contract address
    /// @param forceOverride If true, allows overwriting existing mappings
    /// @dev Only callable by admin role
    function addFunction(bytes4 selector, address implementation, bool forceOverride) public onlyRoles(ADMIN_ROLE) {
        if (!forceOverride) {
            if (selectorToImplementation[selector] != address(0)) revert();
        }
        selectorToImplementation[selector] = implementation;
    }

    /// @notice Adds multiple function selector mappings to an implementation
    /// @param selectors Array of function selectors to add
    /// @param implementation The implementation contract address
    /// @param forceOverride If true, allows overwriting existing mappings
    function addFunctions(bytes4[] calldata selectors, address implementation, bool forceOverride) public {
        for (uint256 i = 0; i < selectors.length; i++) {
            addFunction(selectors[i], implementation, forceOverride);
        }
    }

    /// @notice Removes a function selector mapping
    /// @param selector The function selector to remove
    /// @dev Only callable by admin role
    function removeFunction(bytes4 selector) public onlyRoles(ADMIN_ROLE) {
        delete selectorToImplementation[selector];
    }

    /// @notice Removes multiple function selector mappings
    /// @param selectors Array of function selectors to remove
    function removeFunctions(bytes4[] calldata selectors) public {
        for (uint256 i = 0; i < selectors.length; i++) {
            removeFunction(selectors[i]);
        }
    }

    /// @notice Returns the implementation address for a function selector
    /// @dev Required override from OpenZeppelin Proxy contract
    /// @return The implementation contract address
    function _implementation() internal view override returns (address) {
        bytes4 selector = msg.sig;
        address implementation = selectorToImplementation[selector];
        if (implementation == address(0)) revert();
        return implementation;
    }
}
