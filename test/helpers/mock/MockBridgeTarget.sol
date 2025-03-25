// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

contract MockBridgeTarget {
    bool public wasCalled;
    
    function mockBridgeFunction() public {
        wasCalled = true;
    }
    
    fallback() external payable {
        wasCalled = true;
    }
    
    receive() external payable {
        wasCalled = true;
    }
}

contract MockAllowanceTarget {
    uint256 public allowanceAmount;
    
    function approve(uint256 amount) public {
        allowanceAmount = amount;
    }
}