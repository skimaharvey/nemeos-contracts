// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IDutchAuctionLiquidator {
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
    /* Implementation */
    /**************************************************************************/

    /**
     * @notice Buy liquidated NFT
     * @param liquidatedToken Liquidated token
     * @param liquidatedTokenId Liquidated token ID
     */
    function buy(address liquidatedToken, uint256 liquidatedTokenId) external payable;

    /**
     * @notice Fetch liquidation
     * @param liquidatedToken Liquidated token
     * @param liquidatedTokenId Liquidated token ID
     * @return Liquidation
     */
    function getLiquidation(
        address liquidatedToken,
        uint256 liquidatedTokenId
    ) external view returns (Liquidation memory);

    /**
     * @notice Get current price of liquidation
     * @param liquidatedToken Liquidated token
     * @param liquidatedTokenId Liquidated token ID
     * @return Current price
     */
    function getLiquidationCurrentPrice(
        address liquidatedToken,
        uint256 liquidatedTokenId
    ) external view returns (uint256);

    /**
     * @notice Start a liquidation
     *
     * @param liquidatedToken Liquidated token
     * @param liquidatedTokenId Liquidated token ID
     * @param startingPrice Starting price
     * @param borrower Borrower of liquidated NFT
     */
    function liquidate(
        address liquidatedToken,
        uint256 liquidatedTokenId,
        uint256 startingPrice,
        address borrower
    ) external;

    /**
     * @notice Fetch liquidation
     * @param liquidatedCollection Liquidated collection
     * @param liquidatedTokenId Liquidated token ID
     * @return Liquidation
     */
    function liquidation(
        address liquidatedCollection,
        uint256 liquidatedTokenId
    ) external view returns (Liquidation memory);

    /**
     * @return Duration of a liquidation
     */
    function LIQUIDATION_DURATION() external view returns (uint64);

    /**
     * @return Address of the pools factory
     */
    function POOLS_FACTORY() external view returns (address);
}
