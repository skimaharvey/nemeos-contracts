// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

import {Integration_Test} from "../../../Integration.t.sol";

contract DepositAndVote_Pool_Integration_Fuzz_Test is Integration_Test {
    modifier whenVestingTimeVoteIsNotZero() {
        pool.depositAndVote{value: 1 ether}(users.alice, 0); // depositAndVote with 0 dailyInterestRate to update vestingTimePerLender
        assert(pool.vestingTimePerLender(users.alice) > 0);
        _;
    }

    modifier whenDailyInterestRateVoteIsHigher(uint256 dailyInterestRateVote) {
        // fetch currentPoolDailyInterestRate
        uint256 currentPoolDailyInterestRate = pool.dailyInterestRate();
        // assume dailyInterestRateVote is higher than currentPoolDailyInterestRate
        vm.assume(dailyInterestRateVote > currentPoolDailyInterestRate);
        _;
    }

    modifier whenDailyInterestRateVoteIsLower(uint256 dailyInterestRateVote) {
        // fetch currentPoolDailyInterestRate
        uint256 currentPoolDailyInterestRate = pool.dailyInterestRate();
        // assume dailyInterestRateVote is lower than currentPoolDailyInterestRate
        vm.assume(dailyInterestRateVote < currentPoolDailyInterestRate);
        _;
    }

    modifier whenDeposiing() {
        // initial deposit to create shares
        pool.depositAndVote{value: 1 ether}(users.alice, 0);
        _;
    }

    modifier whenWithdrawing(uint256 firstDeposit) {
        // initial deposit to create shares
        vm.assume(firstDeposit > 0 && firstDeposit < 100 ether);
        pool.depositAndVote{value: firstDeposit}(users.alice, 0);
        _;
    }

    function testFuzz_RevertGiven_NullValue() external {
        vm.expectRevert("Pool: msg.value is 0");
        pool.depositAndVote(users.alice, 1);
    }

    function testFuzz_RevertGiven_InterestRateTooHigh(uint256 dailyInterestRate_) external {
        // fetch maxDailyInterestRate
        uint256 maxDailyInterestRate = pool.maxDailyInterestRate();
        vm.assume(dailyInterestRate_ > maxDailyInterestRate);
        vm.expectRevert("Pool: daily interest rate too high");
        pool.depositAndVote{value: 1 ether}(users.alice, dailyInterestRate_);
    }

    function testFuzz_VestingTimeBecomesHigher(
        uint256 dailyInterestRate_
    ) external whenVestingTimeVoteIsNotZero {
        // fetch Alice's vesting time
        uint256 aliceVestingTimeBefore = pool.vestingTimePerLender(users.alice);

        // fetch maxDailyInterestRate
        uint256 maxDailyInterestRate = pool.maxDailyInterestRate();

        // assume dailyInterestRate_ is valid and superior to 0
        vm.assume(dailyInterestRate_ <= maxDailyInterestRate && dailyInterestRate_ > 0);

        // depositAndVote
        pool.depositAndVote{value: 1 ether}(users.alice, dailyInterestRate_);

        // expect vesting time to not be lower than before
        uint256 aliceVestingTimeAfter = pool.vestingTimePerLender(users.alice);
        assertTrue(aliceVestingTimeAfter > aliceVestingTimeBefore, "vesting time is not higher");
    }

    function testFuzz_DailyInterestRateBecomesHigher(
        uint256 dailyInterestRate_
    ) external whenDailyInterestRateVoteIsHigher(dailyInterestRate_) {
        uint256 dailyInterestRateBefore = pool.dailyInterestRate();
        assertGt(dailyInterestRateBefore, 0);

        // assume dailyInterestRate_ is valid
        uint256 maxDailyInterestRate = pool.maxDailyInterestRate();
        vm.assume(dailyInterestRate_ <= maxDailyInterestRate);

        // depositAndVote
        pool.depositAndVote{value: 1 ether}(users.alice, dailyInterestRate_);

        // expect dailyInterestRate to be superior than before (since dailyInterestRateVote is higher)
        uint256 dailyInterestRateAfter = pool.dailyInterestRate();
        assertTrue(
            dailyInterestRateAfter >= dailyInterestRateBefore,
            "daily interest rate is not higher"
        );
    }

    function testFuzz_DailyInterestRateBecomesLower(
        uint256 dailyInterestRate_
    ) external whenDailyInterestRateVoteIsLower(dailyInterestRate_) {
        uint256 dailyInterestRateBefore = pool.dailyInterestRate();
        assertGt(dailyInterestRateBefore, 0);

        // assume dailyInterestRate_ is valid
        uint256 maxDailyInterestRate = pool.maxDailyInterestRate();
        vm.assume(dailyInterestRate_ <= maxDailyInterestRate);

        // depositAndVote
        pool.depositAndVote{value: 1 ether}(users.alice, dailyInterestRate_);

        // expect dailyInterestRate to be lower than before (since dailyInterestRateVote is lower)
        uint256 dailyInterestRateAfter = pool.dailyInterestRate();
        assertTrue(
            dailyInterestRateAfter <= dailyInterestRateBefore,
            "daily interest rate is not lower"
        );
    }

    function testFuzz_DailyInterestRatePerLenderBecomesHigher(
        uint256 initialDailyRateInBPS_,
        uint256 dailyInterestRateVote_
    ) external {
        // assume dailyInterestRate_ is valid and initial < vote
        uint256 maxDailyInterestRate = pool.maxDailyInterestRate();
        vm.assume(
            dailyInterestRateVote_ <= maxDailyInterestRate &&
                initialDailyRateInBPS_ < dailyInterestRateVote_ &&
                initialDailyRateInBPS_ > 0
        );

        // make first depositAndVote to update dailyInterestRatePerLender
        pool.depositAndVote{value: 1 ether}(users.alice, initialDailyRateInBPS_);

        uint256 dailyInterestRatePerLenderBefore = pool.dailyInterestRatePerLender(users.alice);

        // depositAndVote
        pool.depositAndVote{value: 1 ether}(users.alice, dailyInterestRateVote_);

        // expect dailyInterestRatePerLender to be superior than before (since dailyInterestRateVote is higher)
        uint256 dailyInterestRatePerLenderAfter = pool.dailyInterestRatePerLender(users.alice);
        assertTrue(
            dailyInterestRatePerLenderAfter >= dailyInterestRatePerLenderBefore,
            "daily interest rate per lender is not higher"
        );
    }

    function testFuzz_DailyInterestRatePerLenderBecomesLower(
        uint256 initialDailyRateInBPS_,
        uint256 dailyInterestRateVote_
    ) external {
        // assume dailyInterestRate_ is valid and initial > vote
        uint256 maxDailyInterestRate = pool.maxDailyInterestRate();
        vm.assume(
            initialDailyRateInBPS_ <= maxDailyInterestRate &&
                dailyInterestRateVote_ < maxDailyInterestRate &&
                initialDailyRateInBPS_ > dailyInterestRateVote_ &&
                initialDailyRateInBPS_ > 0
        );

        // make first depositAndVote to update dailyInterestRatePerLender
        pool.depositAndVote{value: 1 ether}(users.alice, initialDailyRateInBPS_);

        uint256 dailyInterestRatePerLenderBefore = pool.dailyInterestRatePerLender(users.alice);

        // depositAndVote
        pool.depositAndVote{value: 1 ether}(users.alice, dailyInterestRateVote_);

        // expect dailyInterestRatePerLender to be lower than before (since dailyInterestRateVote is lower)
        uint256 dailyInterestRatePerLenderAfter = pool.dailyInterestRatePerLender(users.alice);
        assertTrue(
            dailyInterestRatePerLenderAfter <= dailyInterestRatePerLenderBefore,
            "daily interest rate per lender is not lower"
        );
    }

    function testFuzz_SharesIncreases(uint256 depositAmount_) external whenDeposiing {
        // assume depositAmount_ is valid
        vm.assume(depositAmount_ > 0 && depositAmount_ < 99 ether); // 99 ethers because of the 1 ether deposit in whenDeposiing

        // fetch Alice's shares before depositAndVote
        uint256 aliceSharesBefore = pool.balanceOf(users.alice);

        // preview expected shares
        uint256 expectedShares = pool.previewDeposit(depositAmount_);

        // depositAndVote
        pool.depositAndVote{value: depositAmount_}(users.alice, 0);

        // expect Alice's shares to be superior than before
        uint256 aliceSharesAfter = pool.balanceOf(users.alice);

        // expect Alice's shares to be equal to expected shares + shares before
        assertEq(
            aliceSharesAfter,
            aliceSharesBefore + expectedShares,
            "expected shares are not equal to shares after"
        );
    }

    function testFuzz_SharesDecreases(
        uint256 firstDeposit_,
        uint128 amountOfSharesToWithdraw_
    ) external whenWithdrawing(firstDeposit_) {
        // fetch Alice's shares before depositAndVote
        uint256 aliceSharesBefore = pool.balanceOf(users.alice);

        uint256 aliceMaxRedeem = pool.maxRedeem(users.alice);

        vm.assume(amountOfSharesToWithdraw_ <= aliceMaxRedeem);

        // withdraw
        pool.redeem(amountOfSharesToWithdraw_, users.alice, users.alice);

        // expect Alice's shares to be lower than before
        uint256 aliceSharesAfter = pool.balanceOf(users.alice);

        // expect Alice's shares to be equal to shares before - expected shares
        assertEq(
            aliceSharesAfter,
            aliceSharesBefore - amountOfSharesToWithdraw_,
            "expected shares are not equal to shares after"
        );
    }
}
