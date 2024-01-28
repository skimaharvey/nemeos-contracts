// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

// interfaces
import {IDutchAuctionLiquidator} from "./interfaces/IDutchAuctionLiquidator.sol";
import {INFTFilter} from "./interfaces/INFTFilter.sol";
import {INFTWrapper} from "./interfaces/INFTWrapper.sol";
import {ISettlementManager} from "./interfaces/ISettlementManager.sol";
import {IPool} from "./interfaces/IPool.sol";

// libraries
import {ERC4626Upgradeable, IERC20Upgradeable, MathUpgradeable} from "./libs/ModifiedERC4626Upgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Pool
 * @author Maxime Viard
 * @notice ERC4626 pool contract
 */
contract Pool is ERC4626Upgradeable, ReentrancyGuard, IPool {
  using MathUpgradeable for uint256;
  using EnumerableSet for EnumerableSet.Bytes32Set;

  /**************************************************************************/
  /* State  */
  /**************************************************************************/

  /**
   * @dev see {IPool-MAX_LOAN_REFUND_INTERVAL}
   */
  uint256 public constant MAX_LOAN_REFUND_INTERVAL = 30 days;

  /**
   * @dev see {IPool-PROTOCOL_FEE_BASIS_POINTS}
   */
  uint256 public constant PROTOCOL_FEE_BASIS_POINTS = 1500; // 15% of interest fees

  /**
   * @dev see {IPool-BASIS_POINTS}
   */
  uint256 public constant BASIS_POINTS = 10_000;

  /**
   * @dev see {IPool-ltvInBPS}
   */
  uint256 public ltvInBPS;

  /**
   * @dev see {IPool-ltvInBPS}
   */
  address public nftCollection;

  /**
   * @dev see {IPool-ltvInBPS}
   */
  address public liquidator;

  /**
   * @dev see {IPool-nftFilter}
   */
  address public nftFilter;

  /**
   * @dev see {IPool-protocolFeeCollector}
   */
  address public protocolFeeCollector;

  /**
   * @dev see {IPool-wrappedNFT}
   */
  address public wrappedNFT;

  /**
   * @dev see {IPool-vestingTimePerBasisPoint}
   */
  uint256 public vestingTimePerBasisPoint;

  /**
   * @dev see {IPool-dailyInterestRate}
   */
  uint256 public dailyInterestRate;

  /**
   * @dev see {IPool-dailyInterestRatePerLender}
   */
  mapping(address => uint256) public dailyInterestRatePerLender;

  /**
   * @notice Return the Loan with the given ID
   */
  mapping(bytes32 => Loan) private _loans;

  /* All the ongoing loans */
  EnumerableSet.Bytes32Set private _ongoingLoans;

  /* All ongoing liquidations */
  EnumerableSet.Bytes32Set private _ongoingLiquidations;

  /* Vesting time for a specific lender */
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
    uint256 loanToValueinBPS_,
    uint256 initialDailyInterestRateinBPS_,
    address wrappedNFT_,
    address liquidator_,
    address nftFilter_,
    address protocolFeeCollector_
  ) external initializer {
    require(nftCollection_ != address(0), "Pool: nftCollection is zero address");
    require(liquidator_ != address(0), "Pool: liquidator is zero address");
    require(nftFilter_ != address(0), "Pool: NFTFilter is zero address");
    require(protocolFeeCollector_ != address(0), "Pool: protocolFeeCollector is zero address");
    require(ltvInBPS < BASIS_POINTS, "Pool: LTV too high");

    nftCollection = nftCollection_;
    ltvInBPS = loanToValueinBPS_;
    dailyInterestRate = initialDailyInterestRateinBPS_;
    wrappedNFT = wrappedNFT_;
    liquidator = liquidator_;
    nftFilter = nftFilter_;
    protocolFeeCollector = protocolFeeCollector_;
    vestingTimePerBasisPoint = 12 hours;

    string memory collectionName = string.concat("v", Strings.toHexString(loanToValueinBPS_));

    __ERC4626_init(IERC20Upgradeable(address(0)));
    __ERC20_init(collectionName, "vNFTL");
  }

  /**************************************************************************/
  /* Borrower API */
  /**************************************************************************/

  /**
   * @dev see {IPool}
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
  ) external payable nonReentrant {
    /* check that the collection is the same as the one set at deployement */
    require(collectionAddress_ == nftCollection, "Pool: collection address not valid");

    /* check if loan duration is a multiple of 1 day */
    require(loanDuration_ % 1 days == 0, "Pool: loan duration not multiple of 1 day");

    /* check if LTV is respected wit msg.value*/
    uint256 loanDepositLTV = (msg.value * BASIS_POINTS) / priceOfNFT_;
    require(loanDepositLTV >= ltvInBPS, "Pool: LTV not respected");

    uint256 remainingLoanAmount = priceOfNFT_ - msg.value;

    _createLoan(remainingLoanAmount, loanDuration_, priceIncludingFees_, tokenId_);

    /* check if the NFT is valid and the price is correct (NFTFilter) */
    require(
      INFTFilter(nftFilter).verifyLoanValidity(
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
    INFTWrapper(wrappedNFT).mint(tokenId_, msg.sender);

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

  /**
   * @dev see {IPool}
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
      loan.nextPaymentTime = 0;

      /* next payment amount is 0 */
      loan.nextPaiementAmount = 0;

      /* close the loan */
      loan.isClosed = true;

      /* remove the loan from the ongoing loans */
      _ongoingLoans.remove(loanHash);

      /* unwrap NFT */
      _unwrapNFT(tokenId_, borrower_);

      /* emit LoanEntirelyRefunded event */
      emit LoanEntirelyRefunded(nftCollection, loan.tokenID, loan.borrower, loan.amountAtStart);
    } else {
      /* update the loan next payment time to now + interval time */
      loan.nextPaymentTime += MAX_LOAN_REFUND_INTERVAL;

      /* update the loan next payment amount */
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
    _loans[loanHash] = loan;
  }

  /** @dev Allows to liquidate a loan when paiement is late.
   * @param tokenId_ The ID of the NFT.
   * @param borrower_ The address of the borrower.
   */
  function liquidateLoan(uint256 tokenId_, address borrower_) external nonReentrant {
    Loan memory loan = retrieveLoan(tokenId_, borrower_);

    /* check if loan exists */
    require(loan.amountAtStart != 0, "Pool: loan does not exist");

    /* check if loan is not closed or not already in liquidation */
    require(!loan.isClosed && !loan.isInLiquidation, "Pool: loan is closed");

    /* check if loan is expired */
    require(block.timestamp > loan.nextPaymentTime, "Pool: loan paiement not late");

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

    /* transfer NFT to liquidator */
    IERC721(collectionAddress).transferFrom(address(this), liquidator, tokenId_);

    /* call liquidator */
    IDutchAuctionLiquidator(liquidator).liquidate(
      collectionAddress,
      tokenId_,
      loan.amountAtStart,
      borrower_
    );

    /* emit LoanLiquidated event */
    emit LoanLiquidated(collectionAddress, tokenId_, borrower_, liquidator, loan.amountAtStart);
  }

  /**************************************************************************/
  /* Lender API */
  /**************************************************************************/

  /**
   * @dev see {IPool}
   */
  function depositAndVote(
    address receiver_,
    uint256 dailyInterestRate_
  ) external payable returns (uint256) {
    /* check that msg.value is not 0 */
    require(msg.value > 0, "Pool: msg.value is 0");

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
  function mint(uint256, address) public pure override returns (uint256) {
    revert("only native tokens accepted");
  }

  /** @dev See {IERC4626-redeem}.
   * Was modified to include the vesting logic.
   */
  function redeem(
    uint256 shares_,
    address receiver_,
    address owner_
  ) public override returns (uint256) {
    require(block.timestamp >= vestingTimePerLender[owner_], "Pool: vesting time not respected");

    require(shares_ <= maxRedeem(owner_), "ERC4626: redeem more than max");

    uint256 assets = previewRedeem(shares_);
    _withdraw(_msgSender(), receiver_, owner_, assets, shares_);

    return assets;
  }

  /** @dev See {IERC4626-withdraw}.
   * Was modified to include the vesting logic.
   */
  function withdraw(
    uint256 assets_,
    address receiver_,
    address owner_
  ) public override returns (uint256) {
    /* check that vesting time is respected */
    require(block.timestamp >= vestingTimePerLender[owner_], "Pool: vesting time not respected");

    require(assets_ <= maxWithdraw(owner_), "ERC4626: withdraw more than max");

    uint256 shares = previewWithdraw(assets_);

    _withdraw(_msgSender(), receiver_, owner_, assets_, shares);

    return shares;
  }

  /**************************************************************************/
  /* View functions */
  /**************************************************************************/

  /**
   * @dev See {IPool}.
   */
  function calculateLoanPrice(
    uint256 remainingLoanAmount_,
    uint256 loanDurationInDays_
  ) public view returns (uint256, uint256, uint256, uint160) {
    /* make sure Pool has enough fund to lend */
    require(remainingLoanAmount_ <= address(this).balance, "Pool: not enough assets");

    /* number of paiements installments */
    uint256 numberOfInstallments = loanDurationInDays_ % (MAX_LOAN_REFUND_INTERVAL / 1 days) == 0
      ? loanDurationInDays_ / (MAX_LOAN_REFUND_INTERVAL / 1 days)
      : (loanDurationInDays_ / (MAX_LOAN_REFUND_INTERVAL / 1 days)) + 1;

    /* calculate the interests where interest amount is equal number of days * daily interest */
    uint256 totalInterestAmount = (remainingLoanAmount_ * dailyInterestRate * loanDurationInDays_) /
      BASIS_POINTS;

    /* calculate the interest amount per paiement */
    uint256 interestAmountPerPaiement = totalInterestAmount % numberOfInstallments == 0
      ? totalInterestAmount / numberOfInstallments
      : (totalInterestAmount / numberOfInstallments) + 1;

    /* calculate the total amount to be paid back with interest */
    uint256 adjustedRemainingLoanAmountWithInterest = remainingLoanAmount_ +
      interestAmountPerPaiement *
      numberOfInstallments;

    uint256 nextPaiementAmount = adjustedRemainingLoanAmountWithInterest % numberOfInstallments == 0
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

  /** @dev Modified version of {IERC4626-maxWithdraw}
   * returns what is widrawable depending on the balance held by the pool.
   */
  function maxWithdrawAvailable(address owner_) public view returns (uint256) {
    uint256 expectedBalance = _convertToAssets(balanceOf(owner_), MathUpgradeable.Rounding.Down);
    if (expectedBalance >= totalAssets()) {
      return totalAssets();
    } else {
      return expectedBalance;
    }
  }

  /**
   * @dev See {IPool-onGoingLoans}
   */
  function onGoingLoans() external view returns (Loan[] memory onGoingLoansArray) {
    uint256 numberOfOnGoingLoans = _ongoingLoans.length();
    onGoingLoansArray = new Loan[](numberOfOnGoingLoans);
    for (uint256 i = 0; i < numberOfOnGoingLoans; i++) {
      bytes32 loanHash = _ongoingLoans.at(i);
      onGoingLoansArray[i] = _loans[loanHash];
    }
  }

  /**
   * @dev See {IPool-retrieveLoan}
   */
  function retrieveLoan(uint256 tokenId_, address borrower_) public view returns (Loan memory loan) {
    return _loans[keccak256(abi.encodePacked(tokenId_, borrower_))];
  }

  /** @dev Modified version of {IERC4626-totalAssets} that supports ETH as an asset
   * @return The total value of the assets held by the pool at the moment.
   */
  function totalAssetsInPool() public view returns (uint256) {
    return address(this).balance;
  }

  /** @dev Modified version of {IERC4626-totalAssets} that supports ETH as an asset
   * @return The total value of the assets held by the pool at the moment + the on going loans.
   */
  function totalAssets() public view override returns (uint256) {
    /* calculate the total amount owed from onGoingLoans */
    uint256 totatOnGoingLoansAmountOwed;
    uint256 numberOfOnGoingLoans = _ongoingLoans.length();
    for (uint256 i = 0; i < numberOfOnGoingLoans; i++) {
      bytes32 loanHash = _ongoingLoans.at(i);
      Loan memory loan = _loans[loanHash];
      totatOnGoingLoansAmountOwed += (loan.amountOwedWithInterest -
        (loan.remainingNumberOfInstallments * loan.interestAmountPerPaiement));
    }

    /* calculate the total amount owed from onGoingLiquidations */
    uint256 totatOnGoingLiquidationsAmountOwed;
    uint256 numberOfOnGoingLiquidations = _ongoingLiquidations.length();
    for (uint256 i = 0; i < numberOfOnGoingLiquidations; i++) {
      bytes32 loanHash = _ongoingLiquidations.at(i);
      Loan memory loan = _loans[loanHash];
      totatOnGoingLiquidationsAmountOwed += (loan.amountOwedWithInterest -
        (loan.remainingNumberOfInstallments * loan.interestAmountPerPaiement));
    }

    /* equals actual balance + sum of amountOwed in onGoingLoans + sum of amountOwed in onGoingLiquidations */
    return totalAssetsInPool() + totatOnGoingLoansAmountOwed + totatOnGoingLiquidationsAmountOwed;
  }

  /**************************************************************************/
  /* Internals */
  /**************************************************************************/

  function _deposit(
    address caller_,
    address receiver_,
    uint256 assets_,
    uint256 shares_
  ) internal override {
    _mint(receiver_, shares_);
    emit Deposit(caller_, receiver_, assets_, shares_);
  }

  function _convertToShares(
    uint256 assets_,
    MathUpgradeable.Rounding rounding
  ) internal view override returns (uint256) {
    return
      assets_.mulDiv(
        totalSupply() + 10 ** _decimalsOffset(),
        totalAssets() - msg.value + 1, // remove msg.value as it is already accounted for in totalAssets()
        rounding
      );
  }

  function _createLoan(
    uint256 remainingLoanAmount_,
    uint256 loanDuration_,
    uint256 priceIncludingFees_,
    uint256 tokenId_
  ) internal {
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
    _loans[loanHash] = loan;
  }

  function _unwrapNFT(uint256 tokenId_, address borrower_) internal {
    /* burn wrapped NFT */
    INFTWrapper(wrappedNFT).burn(tokenId_);

    /* transfer NFT to borrower */
    IERC721(nftCollection).safeTransferFrom(address(this), borrower_, tokenId_);
  }

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

    uint256 newDailyInterestRate = ((currentDailyInterestRate * previousNumberOfShares) +
      (dailyInterestRate_ * newShares_)) / (previousNumberOfShares + newShares_);

    /* Current dailyInterestRatePerLender */
    uint256 currentDailyInterestRatePerLender = dailyInterestRatePerLender[msg.sender];

    uint256 currentNumberOfShares = balanceOf(msg.sender);

    uint256 newDailyInterestRatePerLender = ((currentDailyInterestRatePerLender *
      currentNumberOfShares) + (dailyInterestRate_ * newShares_)) /
      (currentNumberOfShares + newShares_);

    /* Update the daily interest rate for this specific lender */
    dailyInterestRatePerLender[msg.sender] = newDailyInterestRatePerLender;

    /* Update the daily interest rate of the pool */
    dailyInterestRate = newDailyInterestRate;
  }

  function _updateDailyInterestRateOnWithdrawal(uint256 burntShares_) internal {
    uint256 totalShares = totalSupply();
    uint256 currentDailyInterestRate = dailyInterestRate;

    uint256 newDailyInterestRate = (totalShares - burntShares_) != 0
      ? ((currentDailyInterestRate * totalShares) -
        (dailyInterestRatePerLender[msg.sender] * burntShares_)) / (totalShares - burntShares_)
      : 0;

    /* If all shares of msg.sender are burnt, set their daily interest rate to 0 */
    if (burntShares_ == totalShares) {
      dailyInterestRatePerLender[msg.sender] = 0;
    }

    /* Update the daily interest rate of the pool */
    dailyInterestRate = newDailyInterestRate;
  }

  function _withdraw(
    address caller_,
    address receiver_,
    address owner_,
    uint256 assets_,
    uint256 shares_
  ) internal override {
    // update the vesting time for lender
    _updateDailyInterestRateOnWithdrawal(balanceOf(owner_));

    _burn(owner_, shares_);

    require(receiver_ == owner_, "Pool: receiver is not owner");
    // slither-disable-next-line reentrancy-no-eth
    payable(receiver_).transfer(assets_);

    emit Withdraw(caller_, receiver_, owner_, assets_, shares_);
  }
}
