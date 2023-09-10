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
        // address borrower; // might not be needed
        // address collection; // might not be needed
        // uint256 tokenId; // might not be needed
        uint256 amountAtStart;
        uint256 amountOwed;
        uint256 nextPaiementAmount;
        uint256 loanDuration;
        uint256 interestAmount;
        uint256 startTime;
        uint256 endTime;
        uint256 nextPaymentTime;
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

    /* Number of days you will need to vest for per pecent you are lending at*/
    uint256 public vestingTimePerPerCentInterest = 3 days;

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

    /* Vesting time per borrower */
    mapping(address => uint256) public vestingTimePerBorrower;

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
        uint256 price_,
        address settlementManager_,
        uint256 loanTimestamp_,
        uint256 loanDuration_,
        uint256 maxAmountToBePaidBack_,
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
        uint256 loanDepositLTV = (msg.value * BASIS_POINTS) / price_;
        require(loanDepositLTV >= ltvInBPS, "Pool: LTV not respected");

        uint256 remainingLoanAmount = price_ - msg.value;

        /* check if the amount to be paid back is not too high */
        require(
            _createLoan(remainingLoanAmount, loanDuration_) <= maxAmountToBePaidBack_,
            "Pool: amount to be paid back too high"
        );

        /* check if the loan duration is not too long */
        require(loanDuration_ <= MAX_LOAN_DURATION, "Pool: loan duration too long");

        /* check if the NFT is valid and the price is correct (NFTFilter) */
        require(
            INFTFilter(NFTFilter).verifyLoanValidity(
                collectionAddress_,
                tokenId_,
                price_,
                msg.sender,
                settlementManager_,
                loanTimestamp_,
                orderExtraData_,
                oracleSignature_
            ),
            "Pool: NFT loan not accepted"
        );

        /* buy the NFT */
        ISettlementManager(settlementManager_).executeBuy{value: price_}(
            collectionAddress_,
            tokenId_,
            orderExtraData_
        );

        /* Mint wrapped NFT */
        ICollateralWrapper(wrappedNFT).mint(tokenId_, msg.sender);
    }

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
        require(loan.amountOwed > 0, "Pool: loan already paid back");

        /* check if msg.value is equal to next payment amount */
        require(msg.value == loan.nextPaiementAmount, "Pool: msg.value not equal to next payment");

        /* update the loan */
        loan.amountOwed -= msg.value;

        bytes32 loanHash = keccak256(abi.encodePacked(tokenId_, borrower_));

        if (loan.amountOwed == 0) {
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
            loan.nextPaiementAmount = loan.amountOwed <= loan.nextPaiementAmount
                ? loan.amountOwed
                : loan.nextPaiementAmount;
        }

        /* store the loan */
        loans[loanHash] = loan;
    }

    function liquidateLoan(uint256 tokenId_, address borrower_) external nonReentrant {
        Loan memory loan = retrieveLoan(tokenId_, borrower_);

        /* check if loan exists */
        require(loan.amountAtStart != 0, "Pool: loan does not exist");

        /* check if loan is not closed */
        require(!loan.isClosed && !loan.isInLiquidation, "Pool: loan is closed");

        /* check if loan is expired */
        require(block.timestamp >= loan.nextPaymentTime, "Pool: loan paiement not late");

        /* check if loan is not paid back */
        require(loan.amountOwed > 0, "Pool: loan already paid back");

        /* check if loan is not in liquidation */
        require(!loan.isInLiquidation, "Pool: loan already in liquidation");

        /* put the loan in liquidation */
        loan.isInLiquidation = true;

        bytes32 loanHash = keccak256(abi.encodePacked(tokenId_, borrower_));

        /* remove the loan from the ongoing loans */
        _ongoingLoans.remove(loanHash);

        /* add the loan to the ongoing liquidations */
        _ongoingLiquidations.add(loanHash);

        /* burn wrapped NFT */
        ICollateralWrapper(wrappedNFT).burn(tokenId_);

        address collectionAddress = nftCollection;

        /* transfer NFT to liquidator */
        IERC721(collectionAddress).safeTransferFrom(address(this), liquidator, tokenId_);

        /* call liquidator todo: check with team what price we use as starting liquidation price */
        ICollateralLiquidator(liquidator).liquidate(
            collectionAddress,
            tokenId_,
            loan.amountAtStart
        );
    }

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

    /** @dev Allows to retrieve the loan of a borrower.
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

    /**************************************************************************/
    /* Borrower API Internals */
    /**************************************************************************/

    function _createLoan(
        uint256 remainingLoanAmount,
        uint256 loanDuration_
    ) internal returns (uint256 totalAmountOwed) {
        /* calculate the number of days of the loan */
        uint256 loanDurationInDays = loanDuration_ / 1 days;

        /* calculate the interests where interest amount is equal number of days * daily interest */
        uint256 interestAmount = (remainingLoanAmount * dailyInterestRate * loanDurationInDays) /
            BASIS_POINTS;

        /* calculate the amount to be paid back */
        totalAmountOwed = remainingLoanAmount + interestAmount;

        /* check if pool has enough */
        require(totalAmountOwed <= totalAssets(), "Pool: not enough assets");

        /* calculate end time */
        uint256 endTime = block.timestamp + loanDuration_;

        /* calculate the next payment time */
        uint256 nextPaymentTime = loanDuration_ > MAX_LOAN_REFUND_INTERVAL
            ? block.timestamp + MAX_LOAN_REFUND_INTERVAL
            : block.timestamp + loanDuration_;

        /* calculate the number of paiements installments */
        uint256 numberOfInstallments = loanDurationInDays / (MAX_LOAN_REFUND_INTERVAL / 1 days);

        /* calculate the next paiement amount */
        uint256 nextPaiementAmount = totalAmountOwed % numberOfInstallments == 0
            ? totalAmountOwed / numberOfInstallments
            : (totalAmountOwed / numberOfInstallments) + 1;

        Loan memory loan = Loan({
            amountAtStart: remainingLoanAmount + msg.value,
            amountOwed: totalAmountOwed,
            nextPaiementAmount: nextPaiementAmount,
            loanDuration: loanDuration_,
            interestAmount: interestAmount,
            startTime: block.timestamp,
            endTime: endTime,
            nextPaymentTime: nextPaymentTime,
            isClosed: false,
            isInLiquidation: false
        });

        bytes32 loanHash = keccak256(abi.encodePacked(msg.sender, wrappedNFT, remainingLoanAmount));

        /* add the loan to the ongoing loans */
        _ongoingLoans.add(loanHash);

        /* store the loan */
        loans[loanHash] = loan;
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
     */
    function depositNativeTokens(
        address receiver,
        uint256 dailyInterestRate_
    ) external payable returns (uint256) {
        require(address(_asset) == address(0), "Pool: asset is not ETH");
        require(msg.value > 0, "Pool: msg.value is 0");
        /* check that max daily interest is respected */
        require(dailyInterestRate_ <= MAX_INTEREST_RATE, "Pool: daily interest rate too high");

        require(msg.value <= maxDeposit(receiver), "ERC4626: deposit more than max");

        uint256 shares = previewDeposit(msg.value);

        /* update the daily interest rate with current one */
        _updateDailyInterestRateOnDeposit(dailyInterestRate, shares);

        _deposit(_msgSender(), receiver, msg.value, shares);

        return shares;
    }

    function depositERC20(
        uint256 assets,
        uint256 dailyInterestRate_
    ) external payable returns (uint256) {
        /* check that max daily interest is respected */
        require(dailyInterestRate_ <= MAX_INTEREST_RATE, "Pool: daily interest rate too high");

        _updateVestingTime(dailyInterestRate_);

        /* return the shares minted */
        uint256 shares = deposit(assets, msg.sender);

        /* update the daily interest rate */
        _updateDailyInterestRateOnDeposit(dailyInterestRate_, shares);

        return shares;
    }

    /**************************************************************************/
    /* Lender Internals API */
    /**************************************************************************/

    function _updateVestingTime(uint256 dailyInterestRate_) internal {
        uint256 currentVestingTime = vestingTimePerBorrower[msg.sender];
        uint256 newVestingTime = (dailyInterestRate_ * vestingTimePerPerCentInterest) /
            BASIS_POINTS;
        if (currentVestingTime < newVestingTime) {
            vestingTimePerBorrower[msg.sender] = newVestingTime;
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

    /** @dev See {IERC4626-redeem}.
     * Was modified to include the vesting logic.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        require(
            block.timestamp >= vestingTimePerBorrower[owner],
            "Pool: vesting time not respected"
        );

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
        require(
            block.timestamp >= vestingTimePerBorrower[owner],
            "Pool: vesting time not respected"
        );

        require(assets <= maxWithdraw(owner), "ERC4626: withdraw more than max");

        uint256 shares = previewWithdraw(assets);

        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    /** @dev See {IERC4626-maxWithdraw}.
     * Was modified to return the was is widrawable depending on the balance held by the pool.
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 expectedBalance = _convertToAssets(balanceOf(owner), MathUpgradeable.Rounding.Down);
        if (expectedBalance >= totalAssets()) {
            return totalAssets();
        } else {
            return expectedBalance;
        }
    }

    /** @dev See {IERC4626-totalAssets}.
     * Was modified to support ETH as an asset, and return the balance of the asset held by the pool.
     * @return The total value of the assets held by the pool.
     */
    function totalAssets() public view override returns (uint256) {
        if (address(_asset) == address(0)) {
            return address(this).balance;
        } else {
            return _asset.balanceOf(address(this));
        }
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (address(_asset) != address(0)) {
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

    function updateVestingTimePerPerCentInterest(uint256 vestingTimePerPerCentInterest_) external {
        require(
            msg.sender == protocolFeeCollector,
            "Pool: Only protocol fee collector can update vestingTimePerPerCentInterest"
        );
        vestingTimePerPerCentInterest = vestingTimePerPerCentInterest_;
    }

    // TODO: add pause/unpause logic
}
