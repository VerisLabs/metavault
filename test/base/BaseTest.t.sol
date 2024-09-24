// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test, console2, Vm } from "forge-std/Test.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { Utilities } from "../utils/Utilities.sol";
import { getTokensList } from "../helpers/Tokens.sol";
import { MaxApyCrossChainVaultEvents } from "../helpers/MaxApyCrossChainVaultEvents.sol";

contract BaseTest is Test, MaxApyCrossChainVaultEvents {
    struct Users {
        address payable alice;
        address payable bob;
        address payable eve;
        address payable charlie;
        address payable keeper;
        address payable allocator;
    }

    Utilities public utils;
    Users public users;
    uint256 public chainFork;

    uint256 internal constant MAX_BPS = 10_000;

    function _setUp(string memory chain, uint256 forkBlock) internal virtual {
        if (vm.envOr("FORK", false)) {
            string memory rpc = vm.envString(string.concat("RPC_", chain));
            chainFork = vm.createSelectFork(rpc);
            vm.rollFork(forkBlock);
        }
        // Setup utils
        utils = new Utilities();

        address[] memory tokens = getTokensList(chain);

        // Create users for testing.
        users = Users({
            alice: utils.createUser("Alice", tokens),
            bob: utils.createUser("Bob", tokens),
            eve: utils.createUser("Eve", tokens),
            charlie: utils.createUser("Charlie", tokens),
            keeper: utils.createUser("Keeper", tokens),
            allocator: utils.createUser("Allocator", tokens)
        });

        // Make Alice both the caller and the origin.
        vm.startPrank({ msgSender: users.alice, txOrigin: users.alice });
    }

    function assertRelApproxEq(
        uint256 a,
        uint256 b,
        uint256 maxPercentDelta // An 18 decimal fixed point number, where 1e18 == 100%
    )
        internal
        virtual
    {
        if (b == 0) return assertEq(a, b); // If the expected is 0, actual must be too.

        uint256 percentDelta = ((a > b ? a - b : b - a) * 1e18) / b;

        if (percentDelta > maxPercentDelta) {
            emit log("Error: a ~= b not satisfied [uint]");
            emit log_named_uint("    Expected", b);
            emit log_named_uint("      Actual", a);
            emit log_named_decimal_uint(" Max % Delta", maxPercentDelta, 18);
            emit log_named_decimal_uint("     % Delta", percentDelta, 18);
            fail();
        }
    }

    function assertApproxEq(uint256 a, uint256 b, uint256 maxDelta) internal virtual {
        uint256 delta = a > b ? a - b : b - a;

        if (delta > maxDelta) {
            emit log("Error: a ~= b not satisfied [uint]");
            emit log_named_uint("  Expected", b);
            emit log_named_uint("    Actual", a);
            emit log_named_uint(" Max Delta", maxDelta);
            emit log_named_uint("     Delta", delta);
            fail();
        }
    }
}
