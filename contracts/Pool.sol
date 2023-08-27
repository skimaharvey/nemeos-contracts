// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// interfaces
import {INFTFilter} from "./interfaces/INFTFilter.sol";
import {ISettlementManager} from "./interfaces/ISettlementManager.sol";
import {ICollateralWrapper} from "./interfaces/ICollateralWrapper.sol";
import {ICollateralLiquidator} from "./interfaces/ICollateralLiquidator.sol";

// libraries
import {ERC4626, ERC20, Math, SafeERC20} from "./libs/ModifiedERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Pool is ERC4626, ReentrancyGuard {
    using Math for uint256;
    using EnumerableSet for EnumerableSet.Bytes32Set;

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
    /* Constants */
    /**************************************************************************/

    /* The minimum loan to value ratio */
    uint256 public immutable LTV;

    /* The minimum amount of time of a loan  */
    uint256 MIN_LOAN_DURATION = 1 days;

    /* The maximum amount of time of a loan  */
    uint256 MAX_LOAN_DURATION = 90 days;

    /* The maximum amount of time that can pass between loan payments */
    uint256 MAX_LOAN_REFUND_INTERVAL = 30 days;

    uint256 BASIS_POINTS = 10_000;
    uint256 public constant MAX_INTEREST_RATE = 100; // 1% per day

    /** @dev The address of the contract in charge of liquidating NFT with unpaid loans.
     */
    address public immutable liquidator;

    /** @dev The address of the contract in charge of wrapping NFTs.
     */
    address public immutable wrappedNFT;

    /** @dev The address of the contract in charge of verifying the validity of the loan request.
     */
    address public immutable NFTFilter;

    /** @dev The address of the admin in charge of collecting fees.
     */
    address public immutable protocolAdmin;

    /**************************************************************************/
    /* State */
    /**************************************************************************/

    /* Number of days you will need to vest for per pecent you are lending at*/
    uint256 public vestingTimePerPerCentInterest = 3 days;

    /* The daily interest rate */
    uint256 public dailyInterestRate;

    /* Loans */
    mapping(bytes32 => Loan) public loans;

    /* All the ongoing loans */
    EnumerableSet.Bytes32Set private _ongoingLoans;

    /**************************************************************************/
    /* Constructor */
    /**************************************************************************/
    // TODO: add name/symbol logic to factory
    constructor(
        address asset_,
        uint256 loanToValueinBPS_,
        uint256 initialDailyInterestRateinBPS_,
        string memory name_,
        string memory symbol_,
        address wrappedNFT_,
        address liquidator_,
        address NFTFilter_,
        address protocolFeeCollector_
    ) ERC4626(IERC20(asset_)) ERC20(name_, symbol_) {
        require(liquidator_ != address(0), "Pool: liquidator is zero address");
        require(NFTFilter_ != address(0), "Pool: NFTFilter is zero address");
        require(protocolFeeCollector_ != address(0), "Pool: protocolFeeCollector is zero address");
        LTV = loanToValueinBPS_;
        dailyInterestRate = initialDailyInterestRateinBPS_;
        wrappedNFT = wrappedNFT_;
        liquidator = liquidator_;
        NFTFilter = NFTFilter_;
        protocolAdmin = protocolFeeCollector_;
    }

    /**************************************************************************/
    /* Borrower API */
    /**************************************************************************/

    // todo: add the logic that verify user agrees with total amount to be paid back (may be with slippage)
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
        require(loanDepositLTV >= LTV, "Pool: LTV not respected");

        uint256 remainingLoanAmount = price_ - msg.value;

        /* check if the amount to be paid back is not too high */
        require(
            _createLoan(remainingLoanAmount, loanDuration_) <= maxAmountToBePaidBack_,
            "Pool: amount to be paid back too high"
        );

        /* check if the loan duration is not too long */
        require(loanDuration_ <= MAX_LOAN_DURATION, "Pool: loan duration too long");

        //todo: create internal that will split paiements in n parts depending on the loan duration

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
        ISettlementManager(settlementManager_).executeBuy(
            collectionAddress_,
            tokenId_,
            orderExtraData_
        );

        /* Mint wrapped NFT */
        ICollateralWrapper(wrappedNFT).mint(tokenId_, msg.sender);
    }

    function refundLoan(
        address collectionAddress_,
        uint256 tokenId_,
        address borrower_
    ) external payable nonReentrant {
        Loan memory loan = retrieveLoan(collectionAddress_, tokenId_, borrower_);

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

        bytes32 loanHash = keccak256(abi.encodePacked(collectionAddress_, tokenId_, borrower_));

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
            _unwrapNFT(collectionAddress_, tokenId_, borrower_);
        } else {
            loan.nextPaymentTime += MAX_LOAN_REFUND_INTERVAL;
            loan.nextPaiementAmount = loan.amountOwed <= loan.nextPaiementAmount
                ? loan.amountOwed
                : loan.nextPaiementAmount;
        }

        /* store the loan */
        loans[loanHash] = loan;
    }

    function liquidateLoan(
        address collectionAddress_,
        uint256 tokenId_,
        address borrower_
    ) external nonReentrant {
        Loan memory loan = retrieveLoan(collectionAddress_, tokenId_, borrower_);

        /* check if loan exists */
        require(loan.amountAtStart != 0, "Pool: loan does not exist");

        /* check if loan is not closed */
        require(!loan.isClosed && !loan.isInLiquidation, "Pool: loan is closed");

        /* check if loan is expired */
        require(block.timestamp >= loan.nextPaymentTime, "Pool: loan paiement not late");

        /* check if loan is not paid back */
        require(loan.amountOwed > 0, "Pool: loan already paid back");

        /* close the loan */
        loan.isInLiquidation = true;

        /* remove the loan from the ongoing loans todo: think if we do it from refund or here*/
        _ongoingLoans.remove(keccak256(abi.encodePacked(collectionAddress_, tokenId_, borrower_)));

        /* burn wrapped NFT */
        ICollateralWrapper(wrappedNFT).burn(tokenId_);

        /* transfer NFT to liquidator */
        IERC721(collectionAddress_).safeTransferFrom(address(this), liquidator, tokenId_);

        /* call liquidator todo: check what price we use as starting liquidation price */
        ICollateralLiquidator(liquidator).liquidate(
            collectionAddress_,
            tokenId_,
            loan.amountAtStart
        );
    }

    // todo: review the fact that we use the collection even though it is not needed, maybe the tokenID is enough
    function refundFromLiquidation(
        address collectionAddress_,
        uint256 tokenId_,
        address borrower_
    ) external payable nonReentrant {
        require(msg.sender == liquidator, "Pool: caller is not liquidator");

        Loan memory loan = retrieveLoan(collectionAddress_, tokenId_, borrower_);

        bytes32 loanHash = keccak256(abi.encodePacked(collectionAddress_, tokenId_, borrower_));

        /* remove the loan from the ongoing loans */
        _ongoingLoans.remove(keccak256(abi.encodePacked(collectionAddress_, tokenId_, borrower_)));

        /* update isClosed */
        loan.isClosed = true;

        /* update isInLiquidation */
        loan.isInLiquidation = false;

        /* store the loan */
        loans[loanHash] = loan;
    }

    /** @dev Allows to retrieve the loan of a borrower.
     * @param colectionAddress_ The address of the collection of the NFT.
     * @param tokenId_ The ID of the NFT.
     * @param borrower The address of the borrower.
     * @return loan The loan of the borrower.
     */
    function retrieveLoan(
        address colectionAddress_,
        uint256 tokenId_,
        address borrower
    ) public view returns (Loan memory loan) {
        return loans[keccak256(abi.encodePacked(colectionAddress_, tokenId_, borrower))];
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

    function _unwrapNFT(address collectionAddress_, uint256 tokenId_, address borrower_) internal {
        /* burn wrapped NFT */
        ICollateralWrapper(wrappedNFT).burn(tokenId_);

        /* transfer NFT to borrower */
        IERC721(collectionAddress_).safeTransferFrom(address(this), borrower_, tokenId_);
    }

    /**************************************************************************/
    /* Lender API */
    /**************************************************************************/

    /** @dev Was created in order to deposit native token into the pool when the asset address is address(0).
     */
    function depositNativeToken() external payable {
        require(address(_asset) == address(0), "Pool: asset is not ETH");
        deposit(msg.value, msg.sender);
    }

    /**************************************************************************/
    /* Lender Internals API */
    /**************************************************************************/

    /**************************************************************************/
    /* Overridden Vault API */
    /**************************************************************************/

    /** @dev See {IERC4626-maxWithdraw}.
     * Was modified to return the was is widrawable depending on the balance held by the pool.
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 expectedBalance = _convertToAssets(balanceOf(owner), Math.Rounding.Down);
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
            SafeERC20.safeTransferFrom(_asset, caller, address(this), assets);
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
            SafeERC20.safeTransfer(_asset, receiver, assets);
        }
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /**************************************************************************/
    /* Admin API */
    /**************************************************************************/

    function updateVestingTimePerPerCentInterest(uint256 vestingTimePerPerCentInterest_) external {
        require(
            msg.sender == protocolAdmin,
            "Pool: Only protocol admin can update vestingTimePerPerCentInterest"
        );
        vestingTimePerPerCentInterest = vestingTimePerPerCentInterest_;
    }

    // TODO: add pause/unpause logic
}
