// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

// interfaces
import {IDutchAuctionLiquidator} from "./interfaces/IDutchAuctionLiquidator.sol";
import {INFTFilter} from "./interfaces/INFTFilter.sol";
import {INFTWrapper} from "./interfaces/INFTWrapper.sol";
import {IPool} from "./interfaces/IPool.sol";
import {ISettlementManager} from "./interfaces/ISettlementManager.sol";

// libraries
import {
    ERC4626Upgradeable,
    ERC20Upgradeable,
    SafeERC20Upgradeable,
    IERC20Upgradeable,
    MathUpgradeable
} from "./libs/ModifiedERC4626Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Pool
 * @author Nemeos
 */
contract Pool is ERC4626Upgradeable, ReentrancyGuard, IPool {
    using MathUpgradeable for uint256;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /**************************************************************************/
    /* Events */
    /**************************************************************************/

    /**
     * @dev Emitted when a loan is refunded from liquidation.
     * @param token The address of the NFT collection.
     * @param tokenId The ID of the NFT.
     * @param amount The amount refunded.
     */
    event LoanLiquidationRefund(address indexed token, uint256 indexed tokenId, uint256 amount);

    /**************************************************************************/
    /* State (not updatable after initialization) */
    /**************************************************************************/

    /**
     * @dev see {IPool-BASIS_POINTS}
     */
    uint256 public constant BASIS_POINTS = 10_000;

    /**
     * @dev see {IPool-liquidator}
     */
    address public liquidator;

    /**
     * @dev see {IPool-minimalDepositInBPS}
     */
    uint256 public minimalDepositInBPS;

    /**
     * @dev see {IPool-MIN_LOAN_DURATION}
     */
    uint256 public constant MIN_LOAN_DURATION = 1 days;

    /**
     * @dev see {IPool-MAX_LOAN_DURATION}
     */
    uint256 public constant MAX_LOAN_DURATION = 90 days;

    /**
     * @dev see {IPool-MAX_LOAN_REFUND_INTERVAL}
     */
    uint256 public constant MAX_LOAN_REFUND_INTERVAL = 30 days;

    /**
     * @dev see {IPool-nftCollection}
     */
    address public nftCollection;

    /**
     * @dev see {IPool-nftFilter}
     */
    address public nftFilter;

    /**
     * @dev see {IPool-PROTOCOL_FEE_BASIS_POINTS}
     */
    uint256 public constant PROTOCOL_FEE_BASIS_POINTS = 1500; // 15% of interest fees

    /**
     * @dev see {IPool-protocolFeeCollector}
     */
    address public protocolFeeCollector;

    /**
     * @dev see {IPool-VERSION}
     */
    string public constant VERSION = "1.0.0";

    /**
     * @dev see {IPool-wrappedNFT}
     */
    address public wrappedNFT;

    /**************************************************************************/
    /* State */
    /**************************************************************************/

    /**
     * @dev see {IPool-dailyInterestRate}
     */
    uint256 public dailyInterestRate;

    /**
     * @dev see {IPool-dailyInterestVoteRatePerLender}
     */
    mapping(address => uint256) public dailyInterestVoteRatePerLender;

    /**
     * @dev used to store the liquidation status of a loan
     */
    mapping(bytes32 => Liquidation) private _liquidations;

    /**
     * @dev used to store the state of a loan
     */
    mapping(bytes32 => Loan) private _loans;

    /**
     * @dev see {IPool-maxDailyInterestRate}
     */
    uint256 public maxDailyInterestRate = 100; // 1% per day

    /* All the ongoing loans */
    EnumerableSet.Bytes32Set private _ongoingLoans;

    /* All ongoing liquidations */
    EnumerableSet.Bytes32Set private _ongoingLiquidations;

    /**
     * @dev see {IPool-vestingTimePerBasisPoint}
     */
    uint256 public vestingTimePerBasisPoint;

    /**
     * @dev see {IPool-vestingTimeOfLender}
     */
    mapping(address => uint256) public vestingTimeOfLender;

    /**************************************************************************/
    /* Constructor */
    /**************************************************************************/

    constructor() {
        _disableInitializers();
    }

    /**************************************************************************/
    /* Modifiers */
    /**************************************************************************/

    modifier onlyProtocolFeeCollector() {
        require(msg.sender == protocolFeeCollector, "Pool: caller is not protocol admin");
        _;
    }

    /**************************************************************************/
    /* Initializer */
    /**************************************************************************/

    /**
     * @dev see {IPool-initialize}
     */
    function initialize(
        address nftCollection_,
        uint256 minimalDepositInBPS_,
        uint256 maxPoolDailyLendingRateInBPS_,
        address wrappedNFT_,
        address liquidator_,
        address NFTFilter_,
        address protocolFeeCollector_
    ) external virtual initializer {
        require(nftCollection_ != address(0), "Pool: nftCollection is zero address");
        require(liquidator_ != address(0), "Pool: liquidator is zero address");
        require(NFTFilter_ != address(0), "Pool: NFTFilter is zero address");
        require(protocolFeeCollector_ != address(0), "Pool: protocolFeeCollector is zero address");
        require(minimalDepositInBPS < BASIS_POINTS, "Pool: MinimalDeposit too high");

        nftCollection = nftCollection_;
        minimalDepositInBPS = minimalDepositInBPS_;
        maxDailyInterestRate = maxPoolDailyLendingRateInBPS_;
        wrappedNFT = wrappedNFT_;
        liquidator = liquidator_;
        nftFilter = NFTFilter_;
        protocolFeeCollector = protocolFeeCollector_;
        vestingTimePerBasisPoint = 12 hours;

        // todo: check the naming with team
        string memory collectionName = string.concat(
            Strings.toHexString(nftCollection),
            "-",
            Strings.toHexString(minimalDepositInBPS_)
        );

        __ERC4626_init(IERC20Upgradeable(address(0)));
        __ERC20_init(collectionName, "NFTL"); // todo: check the naming with team
    }

    /**************************************************************************/
    /* Borrower API */
    /**************************************************************************/

    /**
     * @dev see {IPool-buyNFT}
     */
    function buyNFT(
        address collectionAddress_,
        uint256 tokenId_,
        uint256 priceOfNFT_,
        uint256 nftFloorPrice_,
        uint256 priceOfNFTIncludingFees_,
        address settlementManager_,
        uint256 loanTimestamp_,
        uint256 loanDuration_,
        bytes calldata orderExtraData_,
        bytes calldata oracleSignature_
    ) external payable nonReentrant {
        /* check if loan duration is a multiple of 1 day */
        require(loanDuration_ % 1 days == 0, "Pool: loan duration not multiple of 1 day");

        /* check if loan duration is not too long */
        require(loanDuration_ <= MAX_LOAN_DURATION, "Pool: loan duration too long");

        /* check if loan duration is not below 1 day */
        require(loanDuration_ >= MIN_LOAN_DURATION, "Pool: loan duration too short");

        /* price to use to calculate loan */
        uint256 priceToUse = nftFloorPrice_ < priceOfNFT_ ? nftFloorPrice_ : priceOfNFT_;

        /* calculate the rarity premium */
        uint256 rarityPremium = priceOfNFT_ - priceToUse;

        /* check if mininalDeposit is respected wit msg.value
          the rule here is we take the minimum price between the floor price and the price of the NFT
          and then require at deposit that the minimal deposit ratio is respected and if the price of the NFT is
          higher than the floor price we add the difference to the minimal deposit
        */
        require(
            msg.value >= (priceToUse * minimalDepositInBPS) / BASIS_POINTS + rarityPremium,
            "Pool: MinimalDeposit not respected"
        );

        uint256 remainingLoanAmount = priceOfNFT_ - msg.value;

        _createLoan(remainingLoanAmount, loanDuration_, priceOfNFTIncludingFees_, tokenId_);

        /* check if the NFT is valid and the price is correct (NFTFilter) */
        require(
            INFTFilter(nftFilter).verifyLoanValidity(
                collectionAddress_,
                tokenId_,
                priceOfNFT_,
                nftFloorPrice_,
                priceOfNFTIncludingFees_,
                msg.sender,
                settlementManager_,
                loanTimestamp_,
                orderExtraData_,
                oracleSignature_
            ),
            "Pool: NFT loan not accepted"
        );

        /* buy the NFT */
        ISettlementManager(settlementManager_).executeBuy{value: priceOfNFT_}(
            collectionAddress_,
            tokenId_,
            orderExtraData_
        );

        /* Mint wrapped NFT */
        INFTWrapper(wrappedNFT).mint(tokenId_, msg.sender);

        emit LoanStarted(
            collectionAddress_,
            tokenId_,
            msg.sender,
            priceOfNFT_,
            nftFloorPrice_,
            priceOfNFTIncludingFees_,
            settlementManager_,
            loanTimestamp_,
            loanDuration_
        );
    }

    /**
     * @dev see {IPool-calculateLoanPrice}
     */
    function calculateLoanPrice(
        uint256 remainingLoanAmount_,
        uint256 loanDurationInDays_
    ) public view returns (uint256, uint256, uint256, uint160) {
        /* number of payments installments */
        uint256 numberOfInstallments = loanDurationInDays_ % (MAX_LOAN_REFUND_INTERVAL / 1 days) ==
            0
            ? loanDurationInDays_ / (MAX_LOAN_REFUND_INTERVAL / 1 days)
            : (loanDurationInDays_ / (MAX_LOAN_REFUND_INTERVAL / 1 days)) + 1;

        /* calculate the interests where interest amount is equal number of days * daily interest */
        uint256 totalInterestAmount = (remainingLoanAmount_ *
            dailyInterestRate *
            loanDurationInDays_) / BASIS_POINTS;

        /* calculate the interest amount per payment */
        uint256 interestAmountPerPayment = totalInterestAmount % numberOfInstallments == 0
            ? totalInterestAmount / numberOfInstallments
            : (totalInterestAmount / numberOfInstallments) + 1; // +1 wei for liquidity providers

        /* calculate the total amount to be paid back with interest */
        uint256 adjustedRemainingLoanAmountWithInterest = remainingLoanAmount_ +
            interestAmountPerPayment *
            numberOfInstallments;

        uint256 nextPaymentAmount = adjustedRemainingLoanAmountWithInterest %
            numberOfInstallments ==
            0
            ? adjustedRemainingLoanAmountWithInterest / numberOfInstallments
            : (adjustedRemainingLoanAmountWithInterest / numberOfInstallments) + 1;

        /* calculate the amount to be paid back */
        return (
            adjustedRemainingLoanAmountWithInterest,
            interestAmountPerPayment,
            nextPaymentAmount,
            uint160(numberOfInstallments)
        );
    }

    /**
     * @dev see {IPool-getLiquidation}
     */
    function getLiquidation(bytes32 loanHash_) external view returns (Liquidation memory) {
        return _liquidations[loanHash_];
    }

    /**
     * @dev see {IPool-getLoan}
     */
    function getLoan(bytes32 loanHash_) external view returns (Loan memory) {
        return _loans[loanHash_];
    }

    /**
     * @dev see {IPool-forceLiquidateLoan}
     */
    function forceLiquidateLoan(uint256 tokenId_) external nonReentrant {
        Loan memory loan = retrieveLoan(tokenId_, msg.sender);

        /* check if loan exists */
        require(loan.amountAtStart != 0, "Pool: loan does not exist");

        /* check if loan is not closed */
        require(!loan.isClosed && !loan.isInLiquidation, "Pool: loan is closed");

        /* check if loan is not paid back */
        require(loan.amountOwedWithInterest > 0, "Pool: loan already paid back");

        bytes32 loanHash = keccak256(abi.encodePacked(tokenId_, msg.sender));

        /* update the loan to 'in liquidation' */
        _loans[loanHash].isInLiquidation = true;

        /* remove the loan from the ongoing loans */
        _ongoingLoans.remove(loanHash);

        /* add the loan to the ongoing liquidations */
        _ongoingLiquidations.add(loanHash);

        /* burn wrapped NFT */
        INFTWrapper(wrappedNFT).burn(tokenId_);

        address collectionAddress = nftCollection;

        /* Create liquidation */
        _liquidations[loanHash] = Liquidation({
            liquidationStatus: true,
            tokenId: tokenId_,
            startingPrice: loan.amountAtStart,
            startingTimeStamp: block.timestamp,
            endingTimeStamp: block.timestamp +
                IDutchAuctionLiquidator(liquidator).LIQUIDATION_DURATION(),
            borrower: msg.sender,
            remainingAmountOwed: loan.amountOwedWithInterest
        });

        /* transfer NFT to liquidator */
        IERC721(collectionAddress).transferFrom(address(this), liquidator, tokenId_);

        /* call liquidator  */
        IDutchAuctionLiquidator(liquidator).liquidate(
            collectionAddress,
            tokenId_,
            loan.amountAtStart,
            msg.sender
        );

        /* emit LoanLiquidated event */
        emit LoanLiquidated(
            collectionAddress,
            tokenId_,
            msg.sender,
            liquidator,
            loan.amountAtStart
        );
    }

    /**
     * @dev see {IPool-liquidateLoan}
     */
    function liquidateLoan(uint256 tokenId_, address borrower_) external nonReentrant {
        Loan memory loan = retrieveLoan(tokenId_, borrower_);

        /* check if loan exists */
        require(loan.amountAtStart != 0, "Pool: loan does not exist");

        /* check if loan is not closed */
        require(!loan.isClosed && !loan.isInLiquidation, "Pool: loan is closed");

        /* check if loan is expired */
        require(block.timestamp >= loan.nextPaymentTime, "Pool: loan payment not late");

        /* check if loan is not paid back */
        require(loan.amountOwedWithInterest > 0, "Pool: loan already paid back");

        bytes32 loanHash = keccak256(abi.encodePacked(tokenId_, borrower_));

        /* update the loan to 'in liquidation' */
        _loans[loanHash].isInLiquidation = true;

        /* remove the loan from the ongoing loans */
        _ongoingLoans.remove(loanHash);

        /* add the loan to the ongoing liquidations */
        _ongoingLiquidations.add(loanHash);

        /* burn wrapped NFT */
        INFTWrapper(wrappedNFT).burn(tokenId_);

        address collectionAddress = nftCollection;

        /* Create liquidation */
        _liquidations[loanHash] = Liquidation({
            liquidationStatus: true,
            tokenId: tokenId_,
            startingPrice: loan.amountAtStart,
            startingTimeStamp: block.timestamp,
            endingTimeStamp: block.timestamp +
                IDutchAuctionLiquidator(liquidator).LIQUIDATION_DURATION(),
            borrower: borrower_,
            remainingAmountOwed: loan.amountOwedWithInterest
        });

        /* transfer NFT to liquidator */
        IERC721(collectionAddress).transferFrom(address(this), liquidator, tokenId_);

        /* call liquidator  */
        IDutchAuctionLiquidator(liquidator).liquidate(
            collectionAddress,
            tokenId_,
            loan.amountAtStart,
            borrower_
        );

        /* emit LoanLiquidated event */
        emit LoanLiquidated(collectionAddress, tokenId_, borrower_, liquidator, loan.amountAtStart);
    }

    /**
     * @dev see {IPool-onGoingLoans}
     */
    function onGoingLoans() external view returns (Loan[] memory onGoingLoansArray) {
        uint256 length = _ongoingLoans.length();
        onGoingLoansArray = new Loan[](length);
        for (uint256 i = 0; i < length; i++) {
            bytes32 loanHash = _ongoingLoans.at(i);
            onGoingLoansArray[i] = _loans[loanHash];
        }
        return onGoingLoansArray;
    }

    /**
     * @dev see {IPool-refundLoan}
     */
    function refundLoan(uint256 tokenId_, address borrower_) external payable nonReentrant {
        Loan memory loan = retrieveLoan(tokenId_, borrower_);

        /* check if loan exists */
        require(loan.amountAtStart != 0, "Pool: loan does not exist");

        /* check if loan is not closed */
        require(!loan.isClosed && !loan.isInLiquidation, "Pool: loan is closed");

        /* check if loan is not expired or next payment has not passed */
        require(
            block.timestamp < loan.startTime + loan.loanDuration &&
                block.timestamp < loan.nextPaymentTime,
            "Pool: loan expired"
        );

        /* check if loan is not paid back */
        require(loan.amountOwedWithInterest > 0, "Pool: loan already paid back");

        /* check if msg.value is equal to next payment amount */
        require(msg.value == loan.nextPaymentAmount, "Pool: msg.value not equal to next payment");

        /* update the loan */
        loan.amountOwedWithInterest -= msg.value;

        /* calculate protocol fees */
        uint256 protocolFees = (loan.interestAmountPerPayment * PROTOCOL_FEE_BASIS_POINTS) /
            BASIS_POINTS;

        /* mint shares to protocolFeeCollector */
        _mint(protocolFeeCollector, previewDeposit(protocolFees));

        /* update the loan number of installement */
        loan.remainingNumberOfInstallments -= 1;

        bytes32 loanHash = keccak256(abi.encodePacked(tokenId_, borrower_));

        if (loan.amountOwedWithInterest == 0) {
            /* next payment time is now */
            loan.nextPaymentTime = block.timestamp;

            /* next payment amount is 0 */
            loan.nextPaymentAmount = 0;

            /* close the loan */
            loan.isClosed = true;

            /* remove the loan from the ongoing loans */
            _ongoingLoans.remove(loanHash);

            /* unwrap NFT */
            _unwrapNFT(tokenId_, borrower_);

            /* emit LoanEntirelyRefunded event */
            emit LoanEntirelyRefunded(
                nftCollection,
                loan.tokenID,
                loan.borrower,
                loan.amountAtStart
            );
        } else {
            loan.nextPaymentTime += MAX_LOAN_REFUND_INTERVAL;
            loan.nextPaymentAmount = loan.amountOwedWithInterest <= loan.nextPaymentAmount
                ? loan.amountOwedWithInterest
                : loan.nextPaymentAmount;

            /* emit LoanPartiallyRefunded event */
            emit LoanPartiallyRefunded(
                nftCollection,
                loan.tokenID,
                loan.borrower,
                msg.value,
                loan.remainingNumberOfInstallments * loan.nextPaymentAmount
            );
        }

        /* store the loan */
        _loans[loanHash] = loan;
    }

    /**
     * @dev see {IPool-refundFromLiquidation}
     */
    function refundFromLiquidation(
        uint256 tokenId_,
        address borrower_
    ) external payable nonReentrant {
        require(msg.sender == liquidator, "Pool: caller is not liquidator");

        Loan memory loan = retrieveLoan(tokenId_, borrower_);

        bytes32 loanHash = keccak256(abi.encodePacked(tokenId_, borrower_));

        /* find the liquidation */
        Liquidation memory liquidation = _liquidations[loanHash];

        /* check if the refund is higher than the remaining amount owed */
        uint256 refundSurplus = msg.value > liquidation.remainingAmountOwed
            ? msg.value - liquidation.remainingAmountOwed
            : 0;

        /* delete liquidation */
        delete _liquidations[loanHash];

        /* remove the loan from the ongoing loans */
        _ongoingLiquidations.remove(loanHash);

        /* update isClosed */
        loan.isClosed = true;

        /* update isInLiquidation */
        loan.isInLiquidation = false;

        /* store the loan */
        _loans[loanHash] = loan;

        /* take protocol fee out of the interestAmountPerPayment * number of installments remaining * protocolFee */
        uint256 protocolFees = (loan.interestAmountPerPayment *
            loan.remainingNumberOfInstallments *
            PROTOCOL_FEE_BASIS_POINTS) / BASIS_POINTS;

        /* make sure that the protocol fees are not higher than the amount received */
        protocolFees = protocolFees <= msg.value ? protocolFees : msg.value;

        /* mint shares to protocolFeeCollector */
        _mint(protocolFeeCollector, previewDeposit(protocolFees));

        /* refund the surplus to the borrower */
        if (refundSurplus != 0) {
            /* we do not check for success here because we do not want to revert if the transfer fails */
            borrower_.call{value: refundSurplus}("");
        }

        emit LoanLiquidationRefund(nftCollection, tokenId_, msg.value);
    }

    /**
     * @dev see {IPool-retrieveLoan}
     */
    function retrieveLoan(uint256 tokenId_, address borrower_) public view returns (Loan memory) {
        return _loans[keccak256(abi.encodePacked(tokenId_, borrower_))];
    }

    /**************************************************************************/
    /* Borrower API Internals */
    /**************************************************************************/

    function _createLoan(
        uint256 remainingLoanAmount_,
        uint256 loanDuration_,
        uint256 priceOfNFTIncludingFees_,
        uint256 tokenId_
    ) internal returns (uint256) {
        /* calculate the number of days of the loan */
        uint256 loanDurationInDays = loanDuration_ / 1 days;

        require(remainingLoanAmount_ <= address(this).balance, "Pool: not enough assets");

        (
            uint256 amountOwedWithInterest,
            uint256 interestAmountPerPayment,
            uint256 nextPaymentAmount,
            uint160 numberOfInstallments
        ) = calculateLoanPrice(remainingLoanAmount_, loanDurationInDays);

        /* check if the amount to be paid back is not too high */
        require(
            amountOwedWithInterest + msg.value <= priceOfNFTIncludingFees_,
            "Pool: amount to be paid back too high"
        );

        /* calculate the next payment time */
        uint256 nextPaymentTime = loanDuration_ > MAX_LOAN_REFUND_INTERVAL
            ? block.timestamp + MAX_LOAN_REFUND_INTERVAL
            : block.timestamp + loanDuration_;

        Loan memory loan = Loan({
            borrower: msg.sender,
            tokenID: tokenId_,
            amountAtStart: amountOwedWithInterest + msg.value,
            amountOwedWithInterest: amountOwedWithInterest,
            nextPaymentAmount: nextPaymentAmount,
            interestAmountPerPayment: interestAmountPerPayment,
            loanDuration: loanDuration_,
            startTime: block.timestamp,
            nextPaymentTime: nextPaymentTime,
            remainingNumberOfInstallments: numberOfInstallments,
            dailyInterestRateAtStart: dailyInterestRate,
            isClosed: false,
            isInLiquidation: false
        });

        bytes32 loanHash = keccak256(abi.encodePacked(tokenId_, msg.sender));

        /* add the loan to the ongoing loans */
        _ongoingLoans.add(loanHash);

        /* store the loan */
        _loans[loanHash] = loan;

        return amountOwedWithInterest;
    }

    function _currentLiquidatedPrice(
        uint256 startingTimeStamp,
        uint256 endingTimeStamp,
        uint256 startingPrice
    ) internal view returns (uint256) {
        uint256 duration = endingTimeStamp - startingTimeStamp;
        uint256 timeElapsed = block.timestamp - startingTimeStamp;

        uint256 priceDrop = (startingPrice * timeElapsed) / duration;

        if (priceDrop >= startingPrice) {
            return 0;
        }
        return startingPrice - priceDrop;
    }

    function _unwrapNFT(uint256 tokenId_, address borrower_) internal {
        /* burn wrapped NFT */
        INFTWrapper(wrappedNFT).burn(tokenId_);

        /* transfer NFT to borrower */
        IERC721(nftCollection).safeTransferFrom(address(this), borrower_, tokenId_);
    }

    /**************************************************************************/
    /* Lender API */
    /**************************************************************************/

    /**
     * @dev see {IPool-depositAndVote}
     */
    function depositAndVote(
        address receiver_,
        uint256 dailyInterestRate_
    ) external payable returns (uint256) {
        /* check that msg.value is not 0 */
        require(msg.value > 0, "Pool: msg.value is 0");

        /* check that max daily interest is respected */
        require(dailyInterestRate_ <= maxDailyInterestRate, "Pool: daily interest rate too high");

        require(msg.value <= maxDeposit(receiver_), "ERC4626: deposit more than max");

        /* update the vesting time for lender */
        _updateVestingTime(dailyInterestRate_);

        uint256 shares = previewDeposit(msg.value);

        /* update the daily interest rate with current one */
        _updateDailyInterestRateOnDeposit(dailyInterestRate_, shares);

        _deposit(_msgSender(), receiver_, msg.value, shares);

        return shares;
    }

    /**************************************************************************/
    /* Lender Internals API */
    /**************************************************************************/

    function _updateVestingTime(uint256 dailyInterestRate_) internal {
        uint256 currentVestingTime = vestingTimeOfLender[msg.sender];
        uint256 newVestingTime = block.timestamp + (dailyInterestRate_ * vestingTimePerBasisPoint);
        if (currentVestingTime < newVestingTime) {
            vestingTimeOfLender[msg.sender] = newVestingTime;
        }
    }

    function _updateDailyInterestRateOnDeposit(
        uint256 dailyInterestRate_,
        uint256 newShares_
    ) internal {
        uint256 previousNumberOfShares = totalSupply();
        uint256 currentDailyInterestRate = dailyInterestRate;

        uint256 newDailyInterestRate = ((currentDailyInterestRate * previousNumberOfShares) +
            (dailyInterestRate_ * newShares_)) / (previousNumberOfShares + newShares_);

        /* Current dailyInterestVoteRatePerLender */
        uint256 currentDailyInterestVoteRatePerLender = dailyInterestVoteRatePerLender[msg.sender];

        uint256 currentNumberOfShares = balanceOf(msg.sender);

        uint256 newDailyInterestVoteRatePerLender = ((currentDailyInterestVoteRatePerLender *
            currentNumberOfShares) + (dailyInterestRate_ * newShares_)) /
            (currentNumberOfShares + newShares_);

        /* Update the daily interest rate for this specific lender */
        dailyInterestVoteRatePerLender[msg.sender] = newDailyInterestVoteRatePerLender;

        /* Update the daily interest rate of the pool */
        dailyInterestRate = newDailyInterestRate;
    }

    function _updateDailyInterestRateOnWithdrawal(uint256 burntShares, address owner) internal {
        uint256 totalShares = totalSupply();
        uint256 currentDailyInterestRate = dailyInterestRate;

        uint256 newDailyInterestRate = (totalShares - burntShares) != 0
            ? ((currentDailyInterestRate * totalShares) -
                (dailyInterestVoteRatePerLender[owner] * burntShares)) / (totalShares - burntShares)
            : 0;

        /* If all shares of msg.sender are burnt, set their daily interest rate to 0 */
        if (burntShares == totalShares) {
            dailyInterestVoteRatePerLender[owner] = 0;
        }

        /* Update the daily interest rate of the pool */
        dailyInterestRate = newDailyInterestRate;
    }

    /**************************************************************************/
    /* Overridden Vault API */
    /**************************************************************************/

    /** @dev See {IERC4626-deposit}.
     * This function is overriden to prevent deposit of non-native tokens.
     */
    function deposit(uint256, address) public pure override returns (uint256) {
        revert("only native tokens accepted");
    }

    /** @dev See {IERC4626-mint}.
     *
     * This function is overriden to prevent minting of non-native tokens.
     */
    function mint(uint256, address) public pure virtual override returns (uint256) {
        revert("only native tokens accepted");
    }

    /** @dev Modified version of {IERC4626-totalAssets} so that it supports native tokens.
     * @return The total value of the assets held by the pool at the moment.
     */
    function totalAssetsInPool() public view returns (uint256) {
        return address(this).balance;
    }

    /** @dev Modified version of {IERC4626-totalAssets}
     * returns the total assets in Pool plus as well the ongoings loans and liquidations.
     */
    function totalAssets() public view override returns (uint256) {
        /* calculate the total amount owed from onGoingLoans */
        uint256 totatOnGoingLoansAmountOwed;
        uint256 numberOfOnGoingLoans = _ongoingLoans.length();
        for (uint256 i = 0; i < numberOfOnGoingLoans; i++) {
            bytes32 loanHash = _ongoingLoans.at(i);
            Loan memory loan = _loans[loanHash];
            totatOnGoingLoansAmountOwed += loan.amountOwedWithInterest;
        }

        /* calculate the total amount owed from onGoingLiquidations */
        uint256 totatOnGoingLiquidationsAmountOwed;
        uint256 numberOfOnGoingLiquidations = _ongoingLiquidations.length();

        for (uint256 i = 0; i < numberOfOnGoingLiquidations; i++) {
            bytes32 loanHash = _ongoingLiquidations.at(i);
            Liquidation memory liquidation = _liquidations[loanHash];
            totatOnGoingLiquidationsAmountOwed += _currentLiquidatedPrice(
                liquidation.startingTimeStamp,
                liquidation.endingTimeStamp,
                liquidation.startingPrice
            );
        }

        /* equals actual balance + sum of amountOwed in onGoingLoans + sum of amountOwed in onGoingLiquidations */
        return
            totalAssetsInPool() + totatOnGoingLoansAmountOwed + totatOnGoingLiquidationsAmountOwed;
    }

    /** @dev Modified version of {IERC4626-_deposit}
     * Removed logic related to ERC20 tokens.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
    }

    function _convertToShares(
        uint256 assets,
        MathUpgradeable.Rounding rounding
    ) internal view override returns (uint256) {
        return
            assets.mulDiv(
                totalSupply() + 10 ** _decimalsOffset(),
                totalAssets() - msg.value + 1, // remove msg.value as it is already accounted for in totalAssets()
                rounding
            );
    }

    /** @dev Modified version of {IERC4626-_deposit}
     * Added the logic to transfer native tokens.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        /* check that vesting time is respected */
        require(block.timestamp >= vestingTimeOfLender[owner], "Pool: vesting time not respected");

        /* update the vesting time for lender */
        _updateDailyInterestRateOnWithdrawal(balanceOf(owner), owner);

        _burn(owner, shares);

        require(receiver == owner, "Pool: receiver is not owner");

        (bool success, ) = receiver.call{value: assets}("");
        require(success, "Pool: transfer failed");

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /**************************************************************************/
    /* Admin API */
    /**************************************************************************/

    /**
     * @dev see {IPool-updateMaxDailyInterestRate}
     */
    function updateMaxDailyInterestRate(
        uint256 maxDailyInterestRate_
    ) external onlyProtocolFeeCollector {
        require(maxDailyInterestRate_ <= BASIS_POINTS, "Pool: maxDailyInterestRate too high");
        maxDailyInterestRate = maxDailyInterestRate_;

        emit UpdateMaxDailyInterestRate(maxDailyInterestRate_);
    }

    /**
     * @dev see {IPool-updateVestingTimePerBasisPoint}
     */
    function updateVestingTimePerBasisPoint(
        uint256 vestingTimePerBasisPoint_
    ) external onlyProtocolFeeCollector {
        vestingTimePerBasisPoint = vestingTimePerBasisPoint_;

        emit UpdateVestingTimePerBasisPoint(vestingTimePerBasisPoint_);
    }
}
