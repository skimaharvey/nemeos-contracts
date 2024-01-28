// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

// interfaces
import {IDutchAuctionLiquidator} from "./interfaces/IDutchAuctionLiquidator.sol";
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
contract DutchAuctionLiquidator is ReentrancyGuard, Initializable, IDutchAuctionLiquidator {
    /**************************************************************************/
    /* State */
    /**************************************************************************/

    /**
     * @dev see {IDutchAuctionLiquidator-LIQUIDATION_DURATION}
     */
    uint64 public immutable LIQUIDATION_DURATION;

    /**
     * @dev see {IDutchAuctionLiquidator-POOLS_FACTORY}
     */
    address public POOLS_FACTORY;

    /* stores liquidations */
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
        LIQUIDATION_DURATION = liquidationDurationInDays_ * 1 days;
        POOLS_FACTORY = poolsFactory_;
    }

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/

    /**
     * @dev see {IDutchAuctionLiquidator-liquidate}
     */
    function liquidate(
        address liquidatedToken_,
        uint256 liquidatedTokenId_,
        uint256 startingPrice_,
        address borrower_
    ) external nonReentrant {
        /* Check if caller is a pool */
        require(IPoolFactory(POOLS_FACTORY).isPool(msg.sender), "Liquidator: Caller is not a pool");

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
            endingTimeStamp: block.timestamp + LIQUIDATION_DURATION,
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
     * @dev see {IDutchAuctionLiquidator-buy}
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
     * @dev see {IDutchAuctionLiquidator-getLiquidation}
     */
    function getLiquidation(
        address liquidatedToken,
        uint256 liquidatedTokenId
    ) external view returns (Liquidation memory) {
        return _liquidations[liquidatedToken][liquidatedTokenId];
    }

    /**
     * @dev see {IDutchAuctionLiquidator-getLiquidationCurrentPrice}
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
