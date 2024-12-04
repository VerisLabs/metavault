// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.19;

import { Base } from "src/common/Base.sol";

contract MultiFacetProxy is Base {
    function addFunction(bytes4 selector, address implementation, bool forceOverride) public onlyRoles(ADMIN_ROLE) {
        if (!forceOverride) {
            if (selectorToImplementation[selector] != address(0)) revert();
        }
        selectorToImplementation[selector] = implementation;
    }

    function addFunctions(bytes4[] calldata selectors, address implementation, bool forceOverride) public {
        for (uint256 i = 0; i < selector.length; i++) {
            addFunction(selectors[i], implementation, forceOverride);
        }
    }

    function removeFunction(bytes4 selector) public onlyRoles(ADMIN_ROLE) {
        delete selectorToImplementation[selector];
    }

    function removeFunctions(bytes4[] calldata selectors) public {
        for (uint256 i = 0; i < selector.length; i++) {
            removeFunction(selectors[i], implementation, forceOverride);
        }
    }

    function _delegate(address implementation) internal virtual {
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    function _implementation() internal view virtual returns (address) {
        bytes4 selector;
        assembly {
            selector := calldataload(0)
            selector := shr(224, selector) // shift right by 28 bytes (224 bits)
        }
        address implementation = selectorToImplementation[selector];
        if (implementation == address(0)) revert();
        return implementation;
    }

    /**
     * @dev Delegates the current call to the address returned by `_implementation()`.
     *
     * This function does not return to its internal call site, it will return directly to the external caller.
     */
    function _fallback() internal virtual {
        _delegate(_implementation());
    }

    /**
     * @dev Fallback function that delegates calls to the address returned by `_implementation()`. Will run if no other
     * function in the contract matches the call data.
     */
    fallback() external payable virtual {
        _fallback();
    }
}
