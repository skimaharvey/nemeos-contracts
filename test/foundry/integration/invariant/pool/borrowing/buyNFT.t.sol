// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

import {Integration_Test} from "../../../Integration.t.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

contract BuyNFT_Pool_Invariant_Test is Integration_Test, StdInvariant {
    uint256 constant MAX_LOAN_DURATION = 90 days;
    uint256 constant MIN_LOAN_DURATION = 1 days;

    function setUp() public override {
        super.setUp();
        targetContract(address(pool));
    }

    function invariant_loanDurationWithinBounds() public {
        uint256 tokenId = 0; // Assuming tokenId starts from 0
        address borrower = users.alice;
        
        bytes32 loanHash = keccak256(abi.encodePacked(tokenId, borrower));
        IPool.Loan memory loan = pool.getLoan(loanHash);

        if (loan.amountAtStart != 0) { // Check if the loan exists
            assertTrue(loan.loanDuration >= MIN_LOAN_DURATION, "Loan duration below minimum");
            assertTrue(loan.loanDuration <= MAX_LOAN_DURATION, "Loan duration above maximum");
        }
    }

    function invariant_loanAmountNotZero() public {
        uint256 tokenId = 0; // Assuming tokenId starts from 0
        address borrower = users.alice;
        
        bytes32 loanHash = keccak256(abi.encodePacked(tokenId, borrower));
        IPool.Loan memory loan = pool.getLoan(loanHash);

        if (loan.amountAtStart != 0) { // Check if the loan exists
            assertTrue(loan.amountOwedWithInterest > 0, "Loan amount is zero");
        }
    }

    function invariant_loanStartTimeNotInFuture() public {
        uint256 tokenId = 0; // Assuming tokenId starts from 0
        address borrower = users.alice;
        
        bytes32 loanHash = keccak256(abi.encodePacked(tokenId, borrower));
        IPool.Loan memory loan = pool.getLoan(loanHash);

        if (loan.amountAtStart != 0) { // Check if the loan exists
            assertTrue(loan.startTime <= block.timestamp, "Loan start time is in the future");
        }
    }

    function invariant_nextPaymentTimeAfterStartTime() public {
        uint256 tokenId = 0; // Assuming tokenId starts from 0
        address borrower = users.alice;
        
        bytes32 loanHash = keccak256(abi.encodePacked(tokenId, borrower));
        IPool.Loan memory loan = pool.getLoan(loanHash);

        if (loan.amountAtStart != 0) { // Check if the loan exists
            assertTrue(loan.nextPaymentTime > loan.startTime, "Next payment time is not after start time");
        }
    }
}