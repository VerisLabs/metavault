pragma solidity ^0.8.19;

import { SuperPositionsReceiver } from "src/crosschain/SuperPositionsReceiver.sol";

contract SuperPositionsReceiverWrapper is SuperPositionsReceiver {
    constructor(
        uint64 _sourceChain,
        address _gateway,
        address _superPositions,
        address _owner
    )
        SuperPositionsReceiver(_sourceChain, _gateway, _superPositions, _owner)
    { }

    // Additional functionality can be added here if needed
    function setChainId(uint64 _thisChainId) external onlyRoles(ADMIN_ROLE) {
        thisChainId = _thisChainId;
    }
}
