// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IPool {
    /**************************************************************************/
    /* Events */
    /**************************************************************************/

    /**
     * @dev Emitted when a loan is entirely refunded.
     * @param token The address of the NFT collection.
     * @param tokenId The ID of the NFT.
     * @param borrower The address of the borrower.
     * @param amount The amount refunded.
     */
    event LoanEntirelyRefunded(
        address indexed token,
        uint256 indexed tokenId,
        address indexed borrower,
        uint256 amount
    );

    /**
     * @dev Emitted when a loan is liquidated.
     * @param token The address of the NFT collection.
     * @param tokenId The ID of the NFT.
     * @param borrower The address of the borrower.
     * @param liquidator The address of the liquidator.
     * @param amount The amount refunded.
     */
    event LoanLiquidated(
        address indexed token,
        uint256 indexed tokenId,
        address indexed borrower,
        address liquidator,
        uint256 amount
    );

    /**
     * @dev Emitted when a loan is partially refunded.
     * @param token The address of the NFT collection.
     * @param tokenId The ID of the NFT.
     * @param borrower The address of the borrower.
     * @param amountPaid The amount paid.
     * @param amountRemaining The amount remaining.
     */
    event LoanPartiallyRefunded(
        address indexed token,
        uint256 indexed tokenId,
        address indexed borrower,
        uint256 amountPaid,
        uint256 amountRemaining
    );

    /**
     * @dev Emitted when a NFT is bought.
     * @param collectionAddress The address of the NFT collection.
     * @param tokenId The ID of the NFT.
     * @param priceOfNFT The price of the NFT.
     * @param borrower The address of the borrower.
     * @param priceIncludingFees The price of the NFT including fees.
     * @param settlementManager The address of the settlement manager.
     * @param loanTimestamp The timestamp of the loan.
     * @param loanDuration The duration of the loan.
     */
    event LoanStarted(
        address indexed collectionAddress,
        uint256 indexed tokenId,
        address indexed borrower,
        uint256 priceOfNFT,
        uint256 priceIncludingFees,
        address settlementManager,
        uint256 loanTimestamp,
        uint256 loanDuration
    );

    /**
     * @dev Emitted when the vesting time per basis point is updated.
     * @param newVestingTimePerBasisPoint The new vesting time per basis point.
     */
    event UpdateVestingTimePerBasisPoint(uint256 newVestingTimePerBasisPoint);

    /**
     * @dev Emitted when the daily interest rate is updated.
     * @param newMaxDailyInterestRate The new daily interest rate.
     */
    event UpdateMaxDailyInterestRate(uint256 newMaxDailyInterestRate);

    /**************************************************************************/
    /* Structs */
    /**************************************************************************/

    struct Loan {
        address borrower;
        uint256 tokenID;
        uint256 amountAtStart;
        uint256 amountOwedWithInterest;
        uint256 nextPaymentAmount;
        uint256 interestAmountPerPayment;
        uint256 loanDuration;
        uint256 startTime;
        uint256 endTime;
        uint256 nextPaymentTime;
        uint160 remainingNumberOfInstallments;
        bool isClosed;
        bool isInLiquidation;
    }

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/

    /**
     * @notice Get the Basis Points value
     * @return The Basis Points value
     */
    function BASIS_POINTS() external view returns (uint256);

    /**
     * @notice Initiate the loan of an NFT
     * @param collectionAddress_ Address of the NFT collection
     * @param tokenId_ ID of the NFT
     * @param priceOfNFT_ Price of the NFT
     * @param priceIncludingFees_ Price of the NFT including the interest rate and protocol fees
     * @param settlementManager_ Address of the settlement manager that will process the NFT payment
     * @param loanTimestamp_ Timestamp of the loan
     * @param loanDuration_ Duration of the loan
     * @param orderExtraData_ Extra data of the order
     * @param oracleSignature_ Signature of the oracle
     */
    function buyNFT(
        address collectionAddress_,
        uint256 tokenId_,
        uint256 priceOfNFT_,
        uint256 priceIncludingFees_,
        address settlementManager_,
        uint256 loanTimestamp_,
        uint256 loanDuration_,
        bytes calldata orderExtraData_,
        bytes calldata oracleSignature_
    ) external payable;

    /**
     * @notice Allows to calculate the price of a loan.
     * @param remainingLoanAmount The remaining amount of the loan.
     * @param loanDurationInDays The duration of the loan in days.
     * @return adjustedRemainingLoanAmountWithInterest The total amount to be paid back with interest.
     * @return interestAmount The amount of interest to be paid back per paiement.
     * @return nextPaiementAmount The amount to be paid back per paiement.
     * @return numberOfInstallments The number of paiements installments.
     */
    function calculateLoanPrice(
        uint256 remainingLoanAmount,
        uint256 loanDurationInDays
    )
        external
        view
        returns (
            uint256 adjustedRemainingLoanAmountWithInterest,
            uint256 interestAmount,
            uint256 nextPaiementAmount,
            uint160 numberOfInstallments
        );

    /**
     * @notice Return the daily interest rate
     */
    function dailyInterestRate() external view returns (uint256);

    /**
     * @notice Return the daily interest voted by the lender
     */
    function dailyInterestRatePerLender(address lender) external view returns (uint256);

    /**
     * @notice Was created in order to deposit native token into the pool and vote for a daily interest rate.
     * @param receiver The address of the receiver.
     * @param dailyInterestRate The daily interest rate requested by the lender.
     * @return The number of shares minted.
     */
    function depositAndVote(
        address receiver,
        uint256 dailyInterestRate
    ) external payable returns (uint256);

    /**
     * @notice Initialize pool
     * @param nftCollection Address of the NFT collection
     * @param minimalDepositInBPS Minimal deposit in basis points
     * @param wrappedNFT Address of the wrapped NFT
     * @param maxPoolDailyLendingRateInBPS Maximum daily lending rate
     * @param liquidator Address of the liquidator
     * @param NFTFilter Address of the NFT filter
     * @param protocolFeeCollector Address of the protocol fee collector
     */
    function initialize(
        address nftCollection,
        uint256 minimalDepositInBPS,
        uint256 maxPoolDailyLendingRateInBPS,
        address wrappedNFT,
        address liquidator,
        address NFTFilter,
        address protocolFeeCollector
    ) external;

    /**
     * @notice Allows to liquidate a loan when paiement is late.
     * @param tokenId The ID of the NFT.
     * @param borrower The address of the borrower.
     */
    function liquidateLoan(uint256 tokenId, address borrower) external;

    /**
     * @notice Return the minimal deposit required when taking a loan (in basis points)
     */
    function minimalDepositInBPS() external view returns (uint256);

    /**
     * @notice Return the dutch auction liquidator address
     */
    function liquidator() external view returns (address);

    /**
     * @notice Return the maximum loan interval in seconds
     */
    function MAX_LOAN_REFUND_INTERVAL() external view returns (uint256);

    /**
     * @notice Return the nft Collection address that the pool is lending for
     */
    function nftCollection() external view returns (address);

    /**
     * @notice Return the nft filter address that will verify the nft order before lending
     */
    function nftFilter() external view returns (address);

    /**
     * @notice Allows to retrieve the ongoing loans.
     *  @return onGoingLoansArray The array of ongoing loans.
     */
    function onGoingLoans() external view returns (Loan[] memory onGoingLoansArray);

    /**
     * @notice Get the Protocol Fee Basis Points
     *  @return The Protocol Fee Basis Points
     */
    function PROTOCOL_FEE_BASIS_POINTS() external view returns (uint256);

    /**
     * @notice Get the Protocol Fee Collector
     *  @return The Protocol Fee Collector
     */
    function protocolFeeCollector() external view returns (address);

    /**
     * @notice Allows to retrieve a specific loan.
     * @param tokenId The ID of the NFT.
     * @param borrower The address of the borrower.
     * @return The loan of the borrower.
     */
    function retrieveLoan(uint256 tokenId, address borrower) external view returns (Loan memory);

    /**
     * @notice Refund a loan
     * @param tokenId ID of the NFT
     * @param borrower Address of the borrower
     */
    function refundLoan(uint256 tokenId, address borrower) external payable;

    /**
     * @notice Refund a loan from liquidation
     * @param tokenId ID of the NFT
     * @param borrower Address of the borrower
     */
    function refundFromLiquidation(uint256 tokenId, address borrower) external payable;

    /**
     * @notice Return the time you will need to vest for per basis point you are lending at
     * the higher the basis point the longer the vesting time
     */
    function vestingTimePerBasisPoint() external view returns (uint256);

    /**
     * @notice Return the address of the collection wrapper
     */
    function wrappedNFT() external view returns (address);
}
