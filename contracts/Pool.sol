// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// interfaces
import {INFTFilter} from "./interfaces/INFTFilter.sol";

// libraries
import {ERC4626, ERC20, Math, SafeERC20} from "./libs/ModifiedERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Pool is ERC4626, ReentrancyGuard {
    using Math for uint256;

    /**************************************************************************/
    /* Structs */
    /**************************************************************************/

    struct Loan {
        address borrower;
        address collection;
        uint256 tokenId;
        uint256 amountAtStart;
        uint256 amountOwed;
        uint256 loanDuration;
        uint256 interestRate;
        uint256 startTime;
        uint256 endTime;
        uint256 nextPaymentTime;
        bool isClosed;
    }

    /**************************************************************************/
    /* Constants */
    /**************************************************************************/

    /* The minimum loan to value ratio */
    uint256 public immutable LTV;

    /* The maximum amount of time of a loan  */
    uint256 MAX_LOAN_DURATION = 90 days;

    /* The maximum amount of time that can pass between loan payments */
    uint256 MAX_LOAN_REFUND_INTERVAL = 30 days;

    uint256 BASIS_POINTS = 10_000;
    uint256 public constant MAX_INTEREST_RATE = 100; // 1% per day

    /** @dev The address of the contract in charge of liquidating NFT with unpaid loans.
     */
    address public immutable liquidator;

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

    /**************************************************************************/
    /* Constructor */
    /**************************************************************************/
    // TODO: add name/symbol logic to factory
    constructor(
        address asset_,
        uint256 loanToValue_,
        string memory name_,
        string memory symbol_,
        address liquidator_,
        address NFTFilter_,
        address protocolFeeCollector_
    ) ERC4626(IERC20(asset_)) ERC20(name_, symbol_) {
        require(liquidator_ != address(0), "Pool: liquidator is zero address");
        require(NFTFilter_ != address(0), "Pool: NFTFilter is zero address");
        require(protocolFeeCollector_ != address(0), "Pool: protocolFeeCollector is zero address");
        LTV = loanToValue_ * 100; // convert to basis points
        liquidator = liquidator_;
        NFTFilter = NFTFilter_;
        protocolAdmin = protocolFeeCollector_;
    }

    /**************************************************************************/
    /* Pool API */
    /**************************************************************************/

    function buyNFT(
        address collectionAddress_,
        uint256 nftID_,
        uint256 price_,
        address settlementManager_,
        uint256 loanTimestamp_,
        uint256 loanDuration_,
        bytes calldata orderExtraData_,
        bytes calldata oracleSignature_
    ) external payable nonReentrant {
        /* check if LTV is respected wit msg.value*/
        uint256 loanDepositLTV = (msg.value * BASIS_POINTS) / price_;
        require(loanDepositLTV >= LTV, "Pool: LTV not respected");

        uint256 remainingLoanAmount = price_ - msg.value;

        /* check if pool has enough */
        require(remainingLoanAmount <= totalAssets(), "Pool: not enough assets");

        /* check if the loan duration is not too long */
        require(loanDuration_ <= MAX_LOAN_DURATION, "Pool: loan duration too long");

        //todo: create internal that will split paiements in n parts depending on the loan duration

        /* check if the NFT is valid and the price is correct (NFTFilter) */
        require(
            INFTFilter(NFTFilter).verifyLoanValidity(
                collectionAddress_,
                nftID_,
                price_,
                msg.sender,
                marketPlaceAddress_,
                loanTimestamp_,
                orderExtraData_,
                oracleSignature_
            ),
            "Pool: NFT loan not accepted"
        );

        ISettlementManager(settlementManager_).

    }

    /**************************************************************************/
    /* Overridden Vault API */
    /**************************************************************************/

    /** @dev Was created in order to deposit native token into the pool when the asset address is address(0).
     */
    function depositNativeToken() external payable {
        require(address(_asset) == address(0), "Pool: asset is not ETH");
        deposit(msg.value, msg.sender);
    }

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
