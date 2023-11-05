// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

import {Integration_Test} from "../../Integration.t.sol";

contract Lend_Pool is Integration_Test {
    function test_RevertGiven_NullValue() external {
        vm.expectRevert("Pool: msg.value is 0");
        pool.depositAndVote(users.alice, 1);
    }
}
