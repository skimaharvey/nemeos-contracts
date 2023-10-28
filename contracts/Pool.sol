// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// interfaces
import {INFTFilter} from "./interfaces/INFTFilter.sol";
import {ISettlementManager} from "./interfaces/ISettlementManager.sol";
import {ICollateralWrapper} from "./interfaces/ICollateralWrapper.sol";
import {ICollateralLiquidator} from "./interfaces/ICollateralLiquidator.sol";

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

// todo: add fee collecting logic (see with team)
contract Pool is ERC4626Upgradeable, ReentrancyGuard {
    using MathUpgradeable for uint256;
    using EnumerableSet for EnumerableSet.Bytes32Set;

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
     * @dev Emitted when a loan is refunded from liquidation.
     * @param token The address of the NFT collection.
     * @param tokenId The ID of the NFT.
     * @param amount The amount refunded.
     */
    event LoanLiquidationRefund(address indexed token, uint256 indexed tokenId, uint256 amount);

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
        address collection; // to be removed
        uint256 tokenID; // to be removed
        uint256 amountAtStart;
        uint256 amountOwedWithInterest;
        uint256 nextPaiementAmount;
        uint256 interestAmountPerPaiement;
        uint256 loanDuration;
        uint256 startTime;
        uint256 endTime;
        uint256 nextPaymentTime;
        uint160 remainingNumberOfInstallments;
        bool isClosed;
        bool isInLiquidation;
    }

    /**************************************************************************/
    /* State (not updatable after initialization) */
    /**************************************************************************/

    /* The minimum amount of time of a loan  */
    uint256 constant MIN_LOAN_DURATION = 1 days;

    /* The maximum amount of time of a loan  */
    uint256 constant MAX_LOAN_DURATION = 90 days;

    /* The maximum amount of time that can pass between loan payments */
    uint256 constant MAX_LOAN_REFUND_INTERVAL = 30 days;

    /* The protocol fee basis points */
    uint256 public constant PROTOCOL_FEE_BASIS_POINTS = 1500; // 15% of interest fees

    uint256 public constant BASIS_POINTS = 10_000;

    /* The minimum loan to value ratio */
    uint256 public ltvInBPS;

    /* The NFT collection address that this pool lends for */
    address public nftCollection;

    /** @dev The address of the contract in charge of liquidating NFT with unpaid loans.
     */
    address public liquidator;

    /** @dev The address of the contract in charge of verifying the validity of the loan request.
     */
    address public NFTFilter;

    /** @dev The address of the admin in charge of collecting fees.
     */
    address public protocolFeeCollector;

    /** @dev The address of the contract in charge of wrapping NFTs.
     */
    address public wrappedNFT;

    /* The Version of the contract */
    string public constant VERSION = "1.0.0";

    /**************************************************************************/
    /* State */
    /**************************************************************************/

    /* Number of time you will need to vest for per basis point you are lending at*/
    uint256 public vestingTimePerBasisPoint;

    /* The daily interest rate */
    uint256 public dailyInterestRate;

    /* The maximum daily interest rate */
    uint256 public maxDailyInterestRate = 100; // 1% per day

    /* The daily interest rate per lender */
    mapping(address => uint256) public dailyInterestRatePerLender;

    /* Loans */
    mapping(bytes32 => Loan) public loans;

    /* All the ongoing loans */
    EnumerableSet.Bytes32Set private _ongoingLoans;

    /* All ongoing liquidations */
    EnumerableSet.Bytes32Set private _ongoingLiquidations;

    /* Vesting time per lender */
    mapping(address => uint256) public vestingTimePerLender;

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

    function initialize(
        address nftCollection_,
        address asset_,
        uint256 loanToValueinBPS_,
        uint256 initialDailyInterestRateinBPS_,
        uint256 maxDailyInterestRate_,
        address wrappedNFT_,
        address liquidator_,
        address NFTFilter_,
        address protocolFeeCollector_
    ) external initializer {
        require(nftCollection_ != address(0), "Pool: nftCollection is zero address");
        require(liquidator_ != address(0), "Pool: liquidator is zero address");
        require(NFTFilter_ != address(0), "Pool: NFTFilter is zero address");
        require(protocolFeeCollector_ != address(0), "Pool: protocolFeeCollector is zero address");
        require(ltvInBPS < BASIS_POINTS, "Pool: LTV too high");
        require(asset_ == address(0), "Pool: asset should be zero address"); // to be removed later when we support non-native tokens

        nftCollection = nftCollection_;
        ltvInBPS = loanToValueinBPS_;
        dailyInterestRate = initialDailyInterestRateinBPS_;
        maxDailyInterestRate = maxDailyInterestRate_;
        wrappedNFT = wrappedNFT_;
        liquidator = liquidator_;
        NFTFilter = NFTFilter_;
        protocolFeeCollector = protocolFeeCollector_;
        vestingTimePerBasisPoint = 12 hours; // todo: check with team

        // todo: check the naming with team
        string memory collectionName = string.concat(
            Strings.toHexString(nftCollection),
            "-",
            Strings.toHexString(loanToValueinBPS_)
        );

        __ERC4626_init(IERC20Upgradeable(asset_));
        __ERC20_init(collectionName, "NFTL");
    }

    /**************************************************************************/
    /* Borrower API */
    /**************************************************************************/

    // todo: add the logic that verify user agrees with total amount to be paid back (may be with slippage)
    // todo: add settlement manager logic (see with team if need as it is part of the signature and the verification?)
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
    ) external payable nonReentrant {
        /* check if loan duration is a multiple of 1 day */
        require(loanDuration_ % 1 days == 0, "Pool: loan duration not multiple of 1 day");

        /* check if loan duration is not too long */
        require(loanDuration_ <= MAX_LOAN_DURATION, "Pool: loan duration too long");

        /* check if loan duration is not below 1 day */
        require(loanDuration_ >= MIN_LOAN_DURATION, "Pool: loan duration too short");

        /* check if LTV is respected wit msg.value*/
        uint256 loanDepositLTV = (msg.value * BASIS_POINTS) / priceOfNFT_;
        require(loanDepositLTV >= ltvInBPS, "Pool: LTV not respected");

        uint256 remainingLoanAmount = priceOfNFT_ - msg.value;

        _createLoan(remainingLoanAmount, loanDuration_, priceIncludingFees_, tokenId_);

        /* check if the NFT is valid and the price is correct (NFTFilter) */
        require(
            INFTFilter(NFTFilter).verifyLoanValidity(
                collectionAddress_,
                tokenId_,
                priceOfNFT_,
                priceIncludingFees_,
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
        ICollateralWrapper(wrappedNFT).mint(tokenId_, msg.sender);

        emit LoanStarted(
            collectionAddress_,
            tokenId_,
            msg.sender,
            priceOfNFT_,
            priceIncludingFees_,
            settlementManager_,
            loanTimestamp_,
            loanDuration_
        );
    }

    /** @dev Allows to refund a loan.
     * @param tokenId_ The ID of the NFT.
     * @param borrower_ The address of the borrower.
     */
    function refundLoan(uint256 tokenId_, address borrower_) external payable nonReentrant {
        Loan memory loan = retrieveLoan(tokenId_, borrower_);

        /* check if loan exists */
        require(loan.amountAtStart != 0, "Pool: loan does not exist");

        /* check if loan is not closed */
        require(!loan.isClosed && !loan.isInLiquidation, "Pool: loan is closed");

        /* check if loan is not expired */
        require(
            block.timestamp < loan.endTime && block.timestamp < loan.nextPaymentTime,
            "Pool: loan expired"
        );

        /* check if loan is not paid back */
        require(loan.amountOwedWithInterest > 0, "Pool: loan already paid back");

        /* check if msg.value is equal to next payment amount */
        require(msg.value == loan.nextPaiementAmount, "Pool: msg.value not equal to next payment");

        /* update the loan */
        loan.amountOwedWithInterest -= msg.value;

        /* calculate protocol fees */
        uint256 protocolFees = (loan.interestAmountPerPaiement * PROTOCOL_FEE_BASIS_POINTS) /
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
            loan.nextPaiementAmount = 0;

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
            loan.nextPaiementAmount = loan.amountOwedWithInterest <= loan.nextPaiementAmount
                ? loan.amountOwedWithInterest
                : loan.nextPaiementAmount;

            /* emit LoanPartiallyRefunded event */
            emit LoanPartiallyRefunded(
                nftCollection,
                loan.tokenID,
                loan.borrower,
                msg.value,
                loan.remainingNumberOfInstallments * loan.nextPaiementAmount
            );
        }

        /* store the loan */
        loans[loanHash] = loan;
    }

    /** @dev Allows to liquidate a loan when paiement is late.
     * @param tokenId_ The ID of the NFT.
     * @param borrower_ The address of the borrower.
     */
    function liquidateLoan(uint256 tokenId_, address borrower_) external nonReentrant {
        Loan memory loan = retrieveLoan(tokenId_, borrower_);

        /* check if loan exists */
        require(loan.amountAtStart != 0, "Pool: loan does not exist");

        /* check if loan is not closed */
        require(!loan.isClosed && !loan.isInLiquidation, "Pool: loan is closed");

        /* check if loan is expired */
        require(block.timestamp >= loan.nextPaymentTime, "Pool: loan paiement not late");

        /* check if loan is not paid back */
        require(loan.amountOwedWithInterest > 0, "Pool: loan already paid back");

        bytes32 loanHash = keccak256(abi.encodePacked(tokenId_, borrower_));

        /* update the loan to 'in liquidation' */
        loans[loanHash].isInLiquidation = true;

        /* remove the loan from the ongoing loans */
        _ongoingLoans.remove(loanHash);

        /* add the loan to the ongoing liquidations */
        _ongoingLiquidations.add(loanHash);

        /* burn wrapped NFT */
        ICollateralWrapper(wrappedNFT).burn(tokenId_);

        address collectionAddress = nftCollection;

        /* transfer NFT to liquidator */
        IERC721(collectionAddress).transferFrom(address(this), liquidator, tokenId_);

        /* call liquidator todo: check with team what price we use as starting liquidation price */
        ICollateralLiquidator(liquidator).liquidate(
            collectionAddress,
            tokenId_,
            loan.amountAtStart,
            borrower_
        );

        /* emit LoanLiquidated event */
        emit LoanLiquidated(collectionAddress, tokenId_, borrower_, liquidator, loan.amountAtStart);
    }

    /** @dev Called by the liquidator contract to refund the pool after liquidation.
     * @param tokenId_  The ID of the NFT.
     * @param borrower_  The address of the borrower.
     */
    function refundFromLiquidation(
        uint256 tokenId_,
        address borrower_
    ) external payable nonReentrant {
        require(msg.sender == liquidator, "Pool: caller is not liquidator");

        Loan memory loan = retrieveLoan(tokenId_, borrower_);

        bytes32 loanHash = keccak256(abi.encodePacked(tokenId_, borrower_));

        /* remove the loan from the ongoing loans */
        _ongoingLiquidations.remove(loanHash);

        /* update isClosed */
        loan.isClosed = true;

        /* update isInLiquidation */
        loan.isInLiquidation = false;

        /* store the loan */
        loans[loanHash] = loan;

        /* take protocol fee out of the interestAmountPerPaiement * number of installments remaining * protocolFee */
        uint256 protocolFees = (loan.interestAmountPerPaiement *
            loan.remainingNumberOfInstallments *
            PROTOCOL_FEE_BASIS_POINTS) / BASIS_POINTS;

        /* make sure that the protocol fees are not higher than the amount received */
        protocolFees = protocolFees <= msg.value ? protocolFees : msg.value;

        /* convert protocol fees to shares */
        uint256 shares = previewDeposit(protocolFees);

        /* mint shares to protocolFeeCollector */
        _mint(protocolFeeCollector, shares);

        emit LoanLiquidationRefund(nftCollection, tokenId_, msg.value);
    }

    /** @dev Allows to retrieve the ongoing loans.
     *  @return onGoingLoansArray The array of ongoing loans.
     */
    // todo: modify to return a Loan struct array
    function onGoingLoans() external view returns (bytes32[] memory) {
        uint256 length = _ongoingLoans.length();
        bytes32[] memory onGoingLoansArray = new bytes32[](length);
        for (uint256 i = 0; i < length; i++) {
            onGoingLoansArray[i] = _ongoingLoans.at(i);
        }
        return onGoingLoansArray;
    }

    /** @dev Allows to retrieve a specific loan.
     * @param tokenId_ The ID of the NFT.
     * @param borrower The address of the borrower.
     * @return loan The loan of the borrower.
     */
    function retrieveLoan(
        uint256 tokenId_,
        address borrower
    ) public view returns (Loan memory loan) {
        return loans[keccak256(abi.encodePacked(tokenId_, borrower))];
    }

    /** @dev Allows to calculate the price of a loan.
     * @param remainingLoanAmount_ The remaining amount of the loan.
     * @param loanDurationInDays_ The duration of the loan in days.
     * @return adjustedRemainingLoanAmountWithInterest The total amount to be paid back with interest.
     * @return interestAmount The amount of interest to be paid back per paiement.
     * @return nextPaiementAmount The amount to be paid back per paiement.
     * @return numberOfInstallments The number of paiements installments.
     */
    function calculateLoanPrice(
        uint256 remainingLoanAmount_,
        uint256 loanDurationInDays_
    ) public view returns (uint256, uint256, uint256, uint160) {
        require(remainingLoanAmount_ <= address(this).balance, "Pool: not enough assets");

        /* number of paiements installments */
        uint256 numberOfInstallments = loanDurationInDays_ % (MAX_LOAN_REFUND_INTERVAL / 1 days) ==
            0
            ? loanDurationInDays_ / (MAX_LOAN_REFUND_INTERVAL / 1 days)
            : (loanDurationInDays_ / (MAX_LOAN_REFUND_INTERVAL / 1 days)) + 1;

        /* calculate the interests where interest amount is equal number of days * daily interest */
        uint256 totalInterestAmount = (remainingLoanAmount_ *
            dailyInterestRate *
            loanDurationInDays_) / BASIS_POINTS;

        /* calculate the interest amount per paiement */
        uint256 interestAmountPerPaiement = totalInterestAmount % numberOfInstallments == 0
            ? totalInterestAmount / numberOfInstallments
            : (totalInterestAmount / numberOfInstallments) + 1;

        /* calculate the total amount to be paid back with interest */
        uint256 adjustedRemainingLoanAmountWithInterest = remainingLoanAmount_ +
            interestAmountPerPaiement *
            numberOfInstallments;

        uint256 nextPaiementAmount = adjustedRemainingLoanAmountWithInterest %
            numberOfInstallments ==
            0
            ? adjustedRemainingLoanAmountWithInterest / numberOfInstallments
            : (adjustedRemainingLoanAmountWithInterest / numberOfInstallments) + 1;

        /* calculate the amount to be paid back */
        return (
            adjustedRemainingLoanAmountWithInterest,
            interestAmountPerPaiement,
            nextPaiementAmount,
            uint160(numberOfInstallments)
        );
    }

    /**************************************************************************/
    /* Borrower API Internals */
    /**************************************************************************/

    function _createLoan(
        uint256 remainingLoanAmount_,
        uint256 loanDuration_,
        uint256 priceIncludingFees_,
        uint256 tokenId_
    ) internal returns (uint256) {
        /* calculate the number of days of the loan */
        uint256 loanDurationInDays = loanDuration_ / 1 days;

        (
            uint256 amountOwedWithInterest,
            uint256 interestAmountPerPaiement,
            uint256 nextPaiementAmount,
            uint160 numberOfInstallments
        ) = calculateLoanPrice(remainingLoanAmount_, loanDurationInDays);

        /* check if the amount to be paid back is not too high */
        require(
            amountOwedWithInterest + msg.value <= priceIncludingFees_,
            "Pool: amount to be paid back too high"
        );

        /* calculate end time */
        uint256 endTime = block.timestamp + loanDuration_;

        /* calculate the next payment time */
        uint256 nextPaymentTime = loanDuration_ > MAX_LOAN_REFUND_INTERVAL
            ? block.timestamp + MAX_LOAN_REFUND_INTERVAL
            : block.timestamp + loanDuration_;

        Loan memory loan = Loan({
            borrower: msg.sender,
            collection: nftCollection,
            tokenID: tokenId_,
            amountAtStart: amountOwedWithInterest + msg.value,
            amountOwedWithInterest: amountOwedWithInterest,
            nextPaiementAmount: nextPaiementAmount,
            interestAmountPerPaiement: interestAmountPerPaiement,
            loanDuration: loanDuration_,
            startTime: block.timestamp,
            endTime: endTime,
            nextPaymentTime: nextPaymentTime,
            remainingNumberOfInstallments: numberOfInstallments,
            isClosed: false,
            isInLiquidation: false
        });

        bytes32 loanHash = keccak256(abi.encodePacked(tokenId_, msg.sender));

        /* add the loan to the ongoing loans */
        _ongoingLoans.add(loanHash);

        /* store the loan */
        loans[loanHash] = loan;

        return amountOwedWithInterest;
    }

    function _unwrapNFT(uint256 tokenId_, address borrower_) internal {
        /* burn wrapped NFT */
        ICollateralWrapper(wrappedNFT).burn(tokenId_);

        /* transfer NFT to borrower */
        IERC721(nftCollection).safeTransferFrom(address(this), borrower_, tokenId_);
    }

    /**************************************************************************/
    /* Lender API */
    /**************************************************************************/

    /** @dev Was created in order to deposit native token into the pool and vote for a daily interest rate.
     * @param receiver_ The address of the receiver.
     * @param dailyInterestRate_ The daily interest rate requested by the lender.
     * @return shares The number of shares minted.
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
        uint256 currentVestingTime = vestingTimePerLender[msg.sender];
        uint256 newVestingTime = block.timestamp + (dailyInterestRate_ * vestingTimePerBasisPoint);
        if (currentVestingTime < newVestingTime) {
            vestingTimePerLender[msg.sender] = newVestingTime;
        }
    }

    function _updateDailyInterestRateOnDeposit(
        uint256 dailyInterestRate_,
        uint256 newShares_
    ) internal {
        uint256 previousNumberOfShares = totalSupply();
        uint256 currentDailyInterestRate = dailyInterestRate;

        // todo: check calculation
        uint256 newDailyInterestRate = ((currentDailyInterestRate * previousNumberOfShares) +
            (dailyInterestRate_ * newShares_)) / (previousNumberOfShares + newShares_);

        /* Update the daily interest rate for this specific lender */
        dailyInterestRatePerLender[msg.sender] = dailyInterestRate_;

        /* Update the daily interest rate of the pool */
        dailyInterestRate = newDailyInterestRate;
    }

    function _updateDailyInterestRateOnWithdrawal(uint256 burntShares) internal {
        uint256 totalShares = totalSupply();
        uint256 currentDailyInterestRate = dailyInterestRate;

        uint256 newDailyInterestRate = (totalShares - burntShares) != 0
            ? ((currentDailyInterestRate * totalShares) -
                (dailyInterestRatePerLender[msg.sender] * burntShares)) /
                (totalShares - burntShares)
            : 0;

        /* If all shares of msg.sender are burnt, set their daily interest rate to 0 */
        if (burntShares == totalShares) {
            dailyInterestRatePerLender[msg.sender] = 0;
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
    function deposit(uint256, address) public override returns (uint256) {
        revert("only native tokens accepted");
    }

    /** @dev See {IERC4626-mint}.
     *
     * This function is overriden to prevent minting of non-native tokens.
     */
    function mint(uint256, address) public virtual override returns (uint256) {
        revert("only native tokens accepted");
    }

    /** @dev See {IERC4626-redeem}.
     * Was modified to include the vesting logic.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        require(block.timestamp >= vestingTimePerLender[owner], "Pool: vesting time not respected");

        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

    /** @dev See {IERC4626-withdraw}.
     * Was modified to include the vesting logic.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256) {
        /* check that vesting time is respected */
        require(block.timestamp >= vestingTimePerLender[owner], "Pool: vesting time not respected");

        require(assets <= maxWithdraw(owner), "ERC4626: withdraw more than max");

        uint256 shares = previewWithdraw(assets);

        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    /** @dev Modified version of {IERC4626-maxWithdraw}
     * returns what is widrawable depending on the balance held by the pool.
     */
    function maxWithdrawAvailable(address owner) public view returns (uint256) {
        uint256 expectedBalance = _convertToAssets(balanceOf(owner), MathUpgradeable.Rounding.Down);
        if (expectedBalance >= totalAssets()) {
            return totalAssets();
        } else {
            return expectedBalance;
        }
    }

    /** @dev Modified version of {IERC4626-totalAssets} that supports ETH as an asset
     * @return The total value of the assets held by the pool at the moment.
     */
    function totalAssetsInPool() public view returns (uint256) {
        return address(this).balance;
    }

    function totalAssets() public view override returns (uint256) {
        /* calculate the total amount owed from onGoingLoans */
        uint256 totatOnGoingLoansAmountOwed;
        uint256 numberOfOnGoingLoans = _ongoingLoans.length();
        for (uint256 i = 0; i < numberOfOnGoingLoans; i++) {
            bytes32 loanHash = _ongoingLoans.at(i);
            Loan memory loan = loans[loanHash];
            totatOnGoingLoansAmountOwed += (loan.amountOwedWithInterest -
                (loan.remainingNumberOfInstallments * loan.interestAmountPerPaiement));
        }

        /* calculate the total amount owed from onGoingLiquidations */
        //TODO: review logic here
        uint256 totatOnGoingLiquidationsAmountOwed;
        uint256 numberOfOnGoingLiquidations = _ongoingLiquidations.length();
        for (uint256 i = 0; i < numberOfOnGoingLiquidations; i++) {
            bytes32 loanHash = _ongoingLiquidations.at(i);
            Loan memory loan = loans[loanHash];
            totatOnGoingLiquidationsAmountOwed += (loan.amountOwedWithInterest -
                (loan.remainingNumberOfInstallments * loan.interestAmountPerPaiement));
        }

        /* equals actual balance + sum of amountOwed in onGoingLoans + sum of amountOwed in onGoingLiquidations */
        return
            totalAssetsInPool() + totatOnGoingLoansAmountOwed + totatOnGoingLiquidationsAmountOwed;
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
    }

    // todo: fuzz function
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

    // Todo: add the vesting logic
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        _updateDailyInterestRateOnWithdrawal(balanceOf(owner));
        // If _asset is ERC777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.
        _burn(owner, shares);

        require(receiver == owner, "Pool: receiver is not owner");
        // slither-disable-next-line reentrancy-no-eth
        payable(receiver).transfer(assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /**************************************************************************/
    /* Admin API */
    /**************************************************************************/

    function updateVestingTimePerBasisPoint(
        uint256 vestingTimePerBasisPoint_
    ) external onlyProtocolFeeCollector {
        vestingTimePerBasisPoint = vestingTimePerBasisPoint_;

        emit UpdateVestingTimePerBasisPoint(vestingTimePerBasisPoint_);
    }

    function updateMaxDailyInterestRate(uint256 maxDailyInterestRate_) external {
        require(maxDailyInterestRate_ <= BASIS_POINTS, "Pool: maxDailyInterestRate too high");
        maxDailyInterestRate = maxDailyInterestRate_;

        emit UpdateMaxDailyInterestRate(maxDailyInterestRate_);
    }

    // TODO: add pause/unpause logic
}
