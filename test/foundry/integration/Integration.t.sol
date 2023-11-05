// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {Base_Test} from "../Base.t.sol";

contract Integration_Test is Base_Test {
    function setUp() public override {
        super.setUp();

        // // Make alice the default caller in this test suite.
        vm.startPrank({msgSender: users.alice});
    }
}
