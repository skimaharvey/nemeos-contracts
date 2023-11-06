// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

import {Integration_Test} from "../../../Integration.t.sol";

contract BuyNFT_Pool_Integration_Fuzz_Test is Integration_Test {
    function testFuzz_RevertGiven_MaxLoanDuration(uint128 loanDurationInDays_) external {
        uint256 loanDuration_ = uint256(loanDurationInDays_) * 1 days;
        uint256 maxLoanDuration = pool.MAX_LOAN_DURATION();
        vm.assume(loanDuration_ > maxLoanDuration);
        vm.expectRevert("Pool: loan duration too long");
        pool.buyNFT(
            address(collection),
            0,
            0.1 ether,
            0.1 ether,
            address(seaportSettlementManager),
            block.timestamp,
            loanDuration_,
            "",
            ""
        );
    }
}
