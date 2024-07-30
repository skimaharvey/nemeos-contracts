// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

import {Integration_Test} from "../../../Integration.t.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

contract DepositAndVote_Pool_Invariant_Test is Integration_Test, StdInvariant {
    uint256 constant BASIS_POINTS = 10_000;

    function setUp() public override {
        super.setUp();
        targetContract(address(pool));
    }

    function invariant_dailyInterestRateNotExceedMax() public {
        uint256 maxDailyInterestRate = pool.maxDailyInterestRate();
        uint256 currentDailyInterestRate = pool.dailyInterestRate();
        assertTrue(currentDailyInterestRate <= maxDailyInterestRate, "Daily interest rate exceeds maximum");
    }

    function invariant_vestingTimeNotInPast() public {
        uint256 currentVestingTime = pool.vestingTimeOfLender(users.alice);
        assertTrue(currentVestingTime >= block.timestamp, "Vesting time is in the past");
    }

    function invariant_totalAssetsEqualSumOfDepositsAndLoans() public {
        uint256 totalAssets = pool.totalAssets();
        uint256 totalAssetsInPool = pool.totalAssetsInPool();
        
        uint256 totalLoansAmount = 0;
        IPool.Loan[] memory ongoingLoans = pool.onGoingLoans();
        for (uint256 i = 0; i < ongoingLoans.length; i++) {
            totalLoansAmount += ongoingLoans[i].amountOwedWithInterest;
        }

        assertEq(totalAssets, totalAssetsInPool + totalLoansAmount, "Total assets mismatch");
    }

    function invariant_dailyInterestRatePerLenderNotExceedMax() public {
        uint256 maxDailyInterestRate = pool.maxDailyInterestRate();
        uint256 lenderDailyInterestRate = pool.dailyInterestVoteRatePerLender(users.alice);
        assertTrue(lenderDailyInterestRate <= maxDailyInterestRate, "Lender daily interest rate exceeds maximum");
    }

    function invariant_totalSupplyEqualSumOfBalances() public {
        uint256 totalSupply = pool.totalSupply();
        uint256 aliceBalance = pool.balanceOf(users.alice);
        uint256 bobBalance = pool.balanceOf(users.bob);
        uint256 charlieBalance = pool.balanceOf(users.charlie);

        assertEq(totalSupply, aliceBalance + bobBalance + charlieBalance, "Total supply mismatch");
    }
}