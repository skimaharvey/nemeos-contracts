// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// interfaces
import {IPoolFactory} from "./interfaces/IPoolFactory.sol";
import {IPool} from "./interfaces/IPool.sol";

//  libraries
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title Dutch Auction liquidated Liquidator
 * @author Nemeos
 */
contract DutchAuctionLiquidator is ReentrancyGuard, Initializable {
    /**************************************************************************/
    /* Structures */
    /**************************************************************************/

    /**
     * @notice Liquidation
     * @param pool Pool address
     * @param liquidationStatus Liquidation status
     * @param collection Collection address
     * @param tokenId Token ID
     * @param startingPrice Starting price
     * @param startingTimeStamp Starting timestamp
     * @param endingTimeStamp Ending timestamp
     */
    struct Liquidation {
        address pool;
        bool liquidationStatus;
        address collection;
        uint256 tokenId;
        uint256 startingPrice;
        uint256 startingTimeStamp;
        uint256 endingTimeStamp;
        address borrower;
    }

    /**************************************************************************/
    /* Events */
    /**************************************************************************/

    /**
     * @notice Emitted when an liquidation is created
     * @param pool Pool address
     * @param liquidatedToken liquidated token
     * @param liquidatedTokenId liquidated token ID
     * @param borrower Borrower of liquidated NFT
     * @param startingPrice Starting price
     */
    event LiquidationStarted(
        address indexed pool,
        address indexed liquidatedToken,
        uint256 liquidatedTokenId,
        address indexed borrower,
        uint256 startingPrice
    );

    /**
     * @notice Emitted when an liquidation is ended and liquidated is claimed by winner
     * @param liquidatedToken liquidated token
     * @param liquidatedTokenId liquidated token ID
     * @param borrower Borrower of liquidated NFT
     * @param winner Winner of liquidation
     * @param winningPrice Winning price
     */
    event LiquidationEnded(
        address indexed liquidatedToken,
        uint256 liquidatedTokenId,
        address indexed borrower,
        address indexed winner,
        uint256 winningPrice
    );

    /**************************************************************************/
    /* State */
    /**************************************************************************/

    /**
     * @notice Liquidation duration
     */
    uint64 public liquidationDuration = 15 days;

    /**
     * @notice Address of the pools factory
     */
    address public poolsFactory;

    /**
     * @dev NFT liquidation
     */
    mapping(address => mapping(uint256 => Liquidation)) private _liquidations;

    /**************************************************************************/
    /* Constructor */
    /**************************************************************************/

    /**
     * @notice DutchAuctionliquidatedLiquidator constructor
     */
    constructor(address poolsFactory_, uint64 liquidationDurationInDays_) {
        require(
            liquidationDurationInDays_ > 0,
            "DutchAuctionliquidatedLiquidator: Invalid liquidation duration"
        );
        liquidationDuration = liquidationDurationInDays_ * 1 days;
        poolsFactory = poolsFactory_;
    }

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/

    /**
     * @notice Start a liquidation
     *
     * Emits a {LiquidationStarted} event.
     *
     * @param liquidatedToken_ Liquidated token
     * @param liquidatedTokenId_ Liquidated token ID
     * @param startingPrice_ Starting price
     */
    function liquidate(
        address liquidatedToken_,
        uint256 liquidatedTokenId_,
        uint256 startingPrice_,
        address borrower_
    ) external nonReentrant {
        /* Check if caller is a pool */
        require(IPoolFactory(poolsFactory).isPool(msg.sender), "Liquidator: Caller is not a pool");

        /* Check if liquidator owns the tokenId */
        require(
            IERC721(liquidatedToken_).ownerOf(liquidatedTokenId_) == address(this),
            "Liquidator: Liquidator does not own the token"
        );

        /* Create liquidation */
        _liquidations[liquidatedToken_][liquidatedTokenId_] = Liquidation({
            pool: msg.sender,
            liquidationStatus: true,
            collection: liquidatedToken_,
            tokenId: liquidatedTokenId_,
            startingPrice: startingPrice_,
            startingTimeStamp: block.timestamp,
            endingTimeStamp: block.timestamp + liquidationDuration,
            borrower: borrower_
        });

        /* Emit LiquidationStarted */
        emit LiquidationStarted(
            msg.sender,
            liquidatedToken_,
            liquidatedTokenId_,
            borrower_,
            startingPrice_
        );
    }

    /**
     * @notice Buy a liquidation
     *
     * Emits a {LiquidationEnded} event.
     *
     * @param liquidatedToken liquidated token
     * @param liquidatedTokenId liquidated token ID
     */
    function buy(address liquidatedToken, uint256 liquidatedTokenId) external payable nonReentrant {
        /* Get liquidation */
        Liquidation memory liquidation = _liquidations[liquidatedToken][liquidatedTokenId];

        /* Validate liquidation is active */
        require(liquidation.liquidationStatus, "Liquidator: Liquidation is not active");

        /* Delete liquidation */
        delete _liquidations[liquidatedToken][liquidatedTokenId];

        uint256 currentPrice = _currentPrice(
            liquidation.startingTimeStamp,
            liquidation.endingTimeStamp,
            liquidation.startingPrice
        );

        /* Validate bid amount */
        require(msg.value >= currentPrice, "Liquidator: Bid amount is too low");

        /* Emit LiquidationEnded */
        emit LiquidationEnded(
            liquidatedToken,
            liquidatedTokenId,
            liquidation.borrower,
            msg.sender,
            msg.value
        );

        /* Transfer bid amount to pool */
        IPool(liquidation.pool).refundFromLiquidation{value: msg.value}(
            liquidation.tokenId,
            liquidation.borrower
        );

        /* Transfer liquidated to winner */
        IERC721(liquidatedToken).safeTransferFrom(address(this), msg.sender, liquidatedTokenId);
    }

    /**************************************************************************/
    /* Helpers */
    /**************************************************************************/

    /**
     * @notice Get liquidation
     * @param liquidatedToken liquidated token
     * @param liquidatedTokenId liquidated token ID
     * @return Liquidation
     */
    function getLiquidation(
        address liquidatedToken,
        uint256 liquidatedTokenId
    ) external view returns (Liquidation memory) {
        return _liquidations[liquidatedToken][liquidatedTokenId];
    }

    /**
     * @notice Get current price of liquidation
     * @param liquidatedToken liquidated token
     * @param liquidatedTokenId liquidated token ID
     * @return Current price
     */
    function getLiquidationCurrentPrice(
        address liquidatedToken,
        uint256 liquidatedTokenId
    ) external view returns (uint256) {
        Liquidation memory liquidation = _liquidations[liquidatedToken][liquidatedTokenId];
        return
            _currentPrice(
                liquidation.startingTimeStamp,
                liquidation.endingTimeStamp,
                liquidation.startingPrice
            );
    }

    /**************************************************************************/
    /* Internals */
    /**************************************************************************/

    // TODO: add fuzzing test to make sure we cant have rounding errors
    function _currentPrice(
        uint256 startedAt,
        uint256 endingAt,
        uint256 startingPrice
    ) internal view returns (uint256) {
        uint256 duration = endingAt - startedAt;
        uint256 timeElapsed = block.timestamp - startedAt;

        uint256 priceDrop = (startingPrice * timeElapsed) / duration;

        if (priceDrop >= startingPrice) {
            return 0;
        }
        return startingPrice - priceDrop;
    }
}
