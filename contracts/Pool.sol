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

    event LiquidationRefund(
        address indexed collateralToken,
        uint256 indexed collateralTokenId,
        uint256 amount
    );

    /**************************************************************************/
    /* Structs */
    /**************************************************************************/

    struct Loan {
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

    uint256 public constant BASIS_POINTS = 10_000;

    // todo: make it updateable by admin
    uint256 public constant MAX_INTEREST_RATE = 100; // 1% per day

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

    /**************************************************************************/
    /* State */
    /**************************************************************************/

    /* Number of time you will need to vest for per basis point you are lending at*/
    uint256 public vestingTimePerBasisPoint;

    /* The daily interest rate */
    uint256 public dailyInterestRate;

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
    /* Initializer */
    /**************************************************************************/

    function initialize(
        address nftCollection_,
        address asset_,
        uint256 loanToValueinBPS_,
        uint256 initialDailyInterestRateinBPS_,
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
        nftCollection = nftCollection_;
        ltvInBPS = loanToValueinBPS_;
        dailyInterestRate = initialDailyInterestRateinBPS_;
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
        } else {
            loan.nextPaymentTime += MAX_LOAN_REFUND_INTERVAL;
            loan.nextPaiementAmount = loan.amountOwedWithInterest <= loan.nextPaiementAmount
                ? loan.amountOwedWithInterest
                : loan.nextPaiementAmount;
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
    }

    /** @dev Allows to retrieve the ongoing loans.
     *  @return onGoingLoansArray The array of ongoing loans.
     */
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
        /* check if pool has enough balance*/
        if (address(_asset) != address(0)) {
            require(
                remainingLoanAmount_ <= _asset.balanceOf(address(this)),
                "Pool: not enough assets"
            );
        } else {
            require(remainingLoanAmount_ <= address(this).balance, "Pool: not enough assets");
        }

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

    /** @dev Was created in order to deposit native token into the pool when the asset address is address(0).
     * @param receiver_ The address of the receiver.
     * @param dailyInterestRate_ The daily interest rate requested by the lender.
     * @return shares The number of shares minted.
     */
    function depositNativeTokens(
        address receiver_,
        uint256 dailyInterestRate_
    ) external payable returns (uint256) {
        /* check that asset is ETH or else use the the depositERC20 function */
        require(address(_asset) == address(0), "Pool: asset is not ETH");

        /* check that msg.value is not 0 */
        require(msg.value > 0, "Pool: msg.value is 0");

        /* check that max daily interest is respected */
        require(dailyInterestRate_ <= MAX_INTEREST_RATE, "Pool: daily interest rate too high");

        require(msg.value <= maxDeposit(receiver_), "ERC4626: deposit more than max");

        /* update the vesting time for lender */
        _updateVestingTime(dailyInterestRate_);

        uint256 shares = previewDeposit(msg.value);

        /* update the daily interest rate with current one */
        _updateDailyInterestRateOnDeposit(dailyInterestRate_, shares);

        _deposit(_msgSender(), receiver_, msg.value, shares);

        return shares;
    }

    /** @dev Allows to deposit ERC20 tokens into the pool.
     * @param receiver The address of the receiver.
     * @param assets The amount of assets to be deposited.
     * @param dailyInterestRate_ The daily interest rate requested by the lender.
     * @return shares The number of shares minted.
     */
    function depositERC20(
        address receiver,
        uint256 assets,
        uint256 dailyInterestRate_
    ) external returns (uint256) {
        /* check that asset is not ETH or else use the the depositNativeTokens function */
        require(address(_asset) != address(0), "Pool: asset is not ETH");

        /* check that assets is superior to 0 */
        require(assets != 0, "Pool: assets is 0");

        /* check that max daily interest is respected */
        require(dailyInterestRate_ <= MAX_INTEREST_RATE, "Pool: daily interest rate too high");

        require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");

        /* update the vesting time for lender */
        _updateVestingTime(dailyInterestRate_);

        uint256 shares = previewDeposit(assets);

        /* update the daily interest rate with current one */
        _updateDailyInterestRateOnDeposit(dailyInterestRate_, shares);

        _deposit(_msgSender(), receiver, assets, shares);

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

        uint256 newDailyInterestRate = ((currentDailyInterestRate * totalShares) -
            (dailyInterestRatePerLender[msg.sender] * burntShares)) / (totalShares - burntShares);

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
     * This function is still open to non-ETH deposits and users that dont want vote for the daily interest rate.
     */
    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        /* check that asset is not ETH or else use the the depositNativeTokens function */
        require(address(_asset) != address(0), "Pool: asset is ETH");

        require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");

        uint256 shares = previewDeposit(assets);

        /* update the daily interest rate with current one */
        _updateDailyInterestRateOnDeposit(dailyInterestRate, shares);

        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    /** @dev See {IERC4626-mint}.
     *
     * As opposed to {deposit}, minting is allowed even if the vault is in a state where the price of a share is zero.
     * In this case, the shares will be minted without requiring any assets to be deposited.
     */
    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        /* check that asset is not ETH or else use the the depositNativeTokens function */
        require(address(_asset) != address(0), "Pool: asset is ETH");

        require(shares <= maxMint(receiver), "ERC4626: mint more than max");

        uint256 assets = previewMint(shares);

        // /* update the daily interest rate with current one */
        _updateDailyInterestRateOnDeposit(dailyInterestRate, shares);

        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
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
        if (address(_asset) == address(0)) {
            return address(this).balance;
        } else {
            return _asset.balanceOf(address(this));
        }
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
        if (address(_asset) != address(0)) {
            /* safety checks but should not be possible*/
            require(msg.value == 0, "Pool: ETH deposit amount mismatch");
            // If _asset is ERC777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
            // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
            // calls the vault, which is assumed not malicious.
            //
            // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
            // assets are transferred and before the shares are minted, which is a valid state.
            // slither-disable-next-line reentrancy-no-eth
            SafeERC20Upgradeable.safeTransferFrom(_asset, caller, address(this), assets);
        }

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
        if (address(_asset) == address(0)) {
            require(receiver == owner, "Pool: receiver is not owner");
            // slither-disable-next-line reentrancy-no-eth
            payable(receiver).transfer(assets);
        } else {
            if (caller != owner) {
                _spendAllowance(owner, caller, shares);
            }
            // slither-disable-next-line reentrancy-no-eth
            SafeERC20Upgradeable.safeTransfer(_asset, receiver, assets);
        }
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /**************************************************************************/
    /* Admin API */
    /**************************************************************************/

    function updateVestingTimePerBasisPoint(uint256 vestingTimePerBasisPoint_) external {
        require(
            msg.sender == protocolFeeCollector,
            "Pool: Only protocol fee collector can update vestingTimePerBasisPoint"
        );
        vestingTimePerBasisPoint = vestingTimePerBasisPoint_;
    }

    // TODO: add pause/unpause logic
}
