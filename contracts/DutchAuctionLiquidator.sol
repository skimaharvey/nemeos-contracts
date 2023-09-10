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
 * @title Dutch Auction Collateral Liquidator
 * @author Nemeos
 */
contract DutchAuctionCollateralLiquidator is ReentrancyGuard, Initializable {
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
    }

    /**************************************************************************/
    /* Events */
    /**************************************************************************/

    /**
     * @notice Emitted when an liquidation is created
     * @param pool Pool address
     * @param collateralToken Collateral token
     * @param collateralTokenId Collateral token ID
     * @param startingPrice Starting price
     */
    event LiquidationStarted(
        address indexed pool,
        address indexed collateralToken,
        uint256 indexed collateralTokenId,
        uint256 startingPrice
    );

    /**
     * @notice Emitted when an liquidation is ended and collateral is claimed by winner
     * @param collateralToken Collateral token
     * @param collateralTokenId Collateral token ID
     * @param winner Winner of liquidation
     * @param winningPrice Winning price
     */
    event LiquidationEnded(
        address indexed collateralToken,
        uint256 indexed collateralTokenId,
        address indexed winner,
        uint256 winningPrice
    );

    /**************************************************************************/
    /* State */
    /**************************************************************************/

    /**
     * @notice Liquidation duration
     */
    uint64 public _liquidationDuration;

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
     * @notice DutchAuctionCollateralLiquidator constructor
     */
    constructor(address poolsFactory_, uint64 liquidationDurationInDays_) {
        require(
            liquidationDurationInDays_ > 0,
            "DutchAuctionCollateralLiquidator: Invalid liquidation duration"
        );
        _liquidationDuration = liquidationDurationInDays_ * 1 days;
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
     * @param collateralToken_ Collateral token
     * @param collateralTokenId_ Collateral token ID
     * @param startingPrice_ Starting price
     */
    function liquidate(
        address collateralToken_,
        uint256 collateralTokenId_,
        uint256 startingPrice_
    ) external nonReentrant {
        /* Check if caller is a pool */
        require(IPoolFactory(poolsFactory).isPool(msg.sender), "Liquidator: Caller is not a pool");

        /* Check if liquidator owns the tokenId */
        require(
            IERC721(collateralToken_).ownerOf(collateralTokenId_) == address(this),
            "Liquidator: Liquidator does not own the token"
        );

        /* Create liquidation */
        _liquidations[collateralToken_][collateralTokenId_] = Liquidation({
            pool: msg.sender,
            liquidationStatus: true,
            collection: collateralToken_,
            tokenId: collateralTokenId_,
            startingPrice: startingPrice_,
            startingTimeStamp: block.timestamp,
            endingTimeStamp: block.timestamp + _liquidationDuration
        });

        /* Emit LiquidationStarted */
        emit LiquidationStarted(msg.sender, collateralToken_, collateralTokenId_, startingPrice_);
    }

    /**
     * @notice Buy a liquidation
     *
     * Emits a {LiquidationEnded} event.
     *
     * @param collateralToken Collateral token
     * @param collateralTokenId Collateral token ID
     */
    function buy(address collateralToken, uint256 collateralTokenId) external payable nonReentrant {
        /* Get liquidation */
        Liquidation memory liquidation = _liquidations[collateralToken][collateralTokenId];

        /* Validate liquidation is active */
        require(liquidation.liquidationStatus, "Liquidator: Liquidation is not active");

        /* Delete liquidation */
        delete _liquidations[collateralToken][collateralTokenId];

        uint256 currentPrice = _currentPrice(
            liquidation.startingTimeStamp,
            liquidation.endingTimeStamp,
            liquidation.startingPrice
        );

        /* Validate bid amount */
        require(msg.value >= currentPrice, "Liquidator: Bid amount is too low");

        /* Emit LiquidationEnded */
        emit LiquidationEnded(collateralToken, collateralTokenId, msg.sender, currentPrice);

        /* Transfer bid amount to pool */
        IPool(liquidation.pool).refundFromLiquidation{value: msg.value}(liquidation.tokenId);

        /* Transfer collateral to winner */
        IERC721(collateralToken).safeTransferFrom(address(this), msg.sender, collateralTokenId);
    }

    /**************************************************************************/
    /* Helpers */
    /**************************************************************************/

    /**
     * @notice Get liquidation
     * @param collateralToken Collateral token
     * @param collateralTokenId Collateral token ID
     * @return Liquidation
     */
    function getLiquidation(
        address collateralToken,
        uint256 collateralTokenId
    ) external view returns (Liquidation memory) {
        return _liquidations[collateralToken][collateralTokenId];
    }

    /**
     * @notice Get current price of liquidation
     * @param collateralToken Collateral token
     * @param collateralTokenId Collateral token ID
     * @return Current price
     */
    function getLiquidationCurrentPrice(
        address collateralToken,
        uint256 collateralTokenId
    ) external view returns (uint256) {
        Liquidation memory liquidation = _liquidations[collateralToken][collateralTokenId];
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

        if (timeElapsed >= duration) {
            return 0;
        }

        uint256 priceDrop = (startingPrice * timeElapsed) / duration;
        return startingPrice - priceDrop;
    }
}
