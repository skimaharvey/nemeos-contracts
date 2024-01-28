// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IPoolFactory {
    /**************************************************************************/
    /* Events */
    /**************************************************************************/

    /**
     * @notice Emitted when the NFT Wrapper Factory is updated
     * @param oldNftWrapperFactory Old NFT Wrapper Factory address
     * @param newNftWrapperFactory New NFT Wrapper Factory address
     */
    event NftWrapperFactoryUpdated(
        address indexed oldNftWrapperFactory,
        address indexed newNftWrapperFactory
    );

    /**
     * @notice Emitted when a pool is created
     * @param collection Collection address
     * @param minimalDeposit minimal deposit in BPS
     * @param pool Pool address
     * @param deployer Pool deployer address
     */
    event PoolCreated(
        address indexed collection,
        uint256 minimalDeposit,
        address indexed pool,
        address indexed deployer
    );

    /**
     * @notice Emitted when the allowed liquidators are updated
     * @param allowedLiquidators New allowed liquidators
     */
    event UpdateAllowedLiquidators(address[] allowedLiquidators);

    /**
     * @notice Emitted when the minimal deposit values are updated
     * @param allowedMinimalDeposits New allowed minimal deposits
     */
    event UpdateAllowedMinimalDepositsInBPS(uint256[] allowedMinimalDeposits);

    /**
     * @notice Emitted when the allowed NFT filters are updated
     * @param allowedNFTFilters New allowed NFT filters
     */
    event UpdateAllowedNFTFilters(address[] allowedNFTFilters);

    /**
     * @notice Emitted when the minimal deposit at creation is updated
     * @param minimalDepositAtCreation New minimal deposit at creation
     */
    event UpdateMinimalDepositAtCreation(uint256 minimalDepositAtCreation);

    /**
     * @notice Emitted when the max pool daily interest rate is updated
     * @param maxPoolDailyLendingRateInBPS New max pool daily interest rate
     */
    event UpdateMaxPoolDailyLendingRateInBPS(uint256 maxPoolDailyLendingRateInBPS);

    /**
     * @notice Emitted when the NFT Wrapper Factory is updated
     * @param newNftWrapperFactory New NFT Wrapper Factory address
     */
    event UpdateNFTWrapperFactory(address indexed newNftWrapperFactory);

    /**
     * @notice Emitted when the pool implementation is updated
     * @param poolImplementation New pool implementation address
     */
    event UpdatePoolImplementation(address indexed poolImplementation);

    /**
     * @notice Emitted when the protocol fee collector is updated
     * @param protocolFeeCollector New protocol fee collector address
     */
    event UpdateProtocolFeeCollector(address indexed protocolFeeCollector);

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/

    /**
     * Create a 1167 proxy pool instance
     * @param collection Collection address
     * @param minimalDepositInBPS Minimal deposit in BPS
     * @param initialDailyInterestRateInBPS Initial daily interest rate
     * @param nftFilter NFT filter collection address
     * @param liquidator Liquidator address (used to liquidate non paid loans)
     * @return Pool address
     */
    function createPool(
        address collection,
        uint256 minimalDepositInBPS,
        uint256 initialDailyInterestRateInBPS,
        address nftFilter,
        address liquidator
    ) external payable returns (address);

    /**
     * @notice Initialize the factory
     * @param factoryOwner Factory owner address
     * @param protocolFeeCollector Protocol fee collector address
     * @param minimalDepositAtCreation Minimal deposit at creation
     * @param maxPoolDailyLendingRateInBPS Max pool daily interest rate
     */
    function initialize(
        address factoryOwner,
        address protocolFeeCollector,
        uint256 minimalDepositAtCreation,
        uint256 maxPoolDailyLendingRateInBPS
    ) external;

    /**
     * @notice Check if address is a pool
     * @param pool Pool address
     * @return True if address is a pool, otherwise false
     */
    function isPool(address pool) external view returns (bool);

    /**
     * @notice Get the allowed minimal deposits in BPS
     * @return The allowed minimal deposits in BPS
     */
    function getAllowedMinimalDepositsInBPSs() external view returns (uint256[] memory);

    /**
     * @notice Get the allowed NFT Filters
     * @return The sllowed NFT Filters
     */
    function getAllowedNFTFilters() external view returns (address[] memory);

    /**
     * @notice Get Proxy Implementation of the factory
     * @return Implementation address
     */
    function getImplementation() external view returns (address);

    /**
     * @notice Get the the pool address by collection and minimal deposits
     * @param collection Collection address
     * @param minimalDepositInBPS Minimal deposit in BPS
     * @return Pool address
     */
    function getPoolByCollectionAndMinimalDeposits(
        address collection,
        uint256 minimalDepositInBPS
    ) external view returns (address);

    /**
     * @notice Get list of pools
     * @return List of pool addresses
     */
    function getPools() external view returns (address[] memory);

    /**
     * @notice Get count of pools
     * @return Count of pools
     */
    function getPoolCount() external view returns (uint256);

    /**
     * @notice Get the max pool daily interest rate
     * @return Return the max pool daily interest rate
     */
    function maxPoolDailyLendingRateInBPS() external view returns (uint256);

    /**
     * @notice Get Minimal deposit at creation to avoid inflation attack
     * @return Return minimal deposit at creation
     */
    function minimalDepositAtCreation() external view returns (uint256);

    /**
     * @notice Get NFT Wrapper Factory address
     * @return NFT Wrapper Factory address
     */
    function nftWrapperFactory() external view returns (address);

    /**
     * @notice Get the pool implementation address
     * @return Pool implementation address
     */
    function poolImplementation() external view returns (address);

    /**
     * @notice Get the protocol fee collector address
     * @return Protocol fee collector address
     */
    function protocolFeeCollector() external view returns (address);

    /**
     * @notice Update the allowed Minimal Deposits in BPS
     */
    function updateAllowedMinimalDepositsInBPS(uint256[] memory allowedMinimalDeposits) external;

    /**
     * @notice Update the allowed Liquidators
     */
    function updateAllowedLiquidators(address[] memory allowedLiquidators) external;

    /**
     * @notice Update the allowed NFT Filters
     */
    function updateAllowedNFTFilters(address[] memory allowedNFTFilters) external;

    /**
     * @notice Update the NFTWrapper factory address
     * @param NFTWrapperFactory NFTWrapper factory address
     */
    function updateNFTWrapperFactory(address NFTWrapperFactory) external;

    /**
     * @notice Update the Max Pool Daily Lending Rate In BPS
     */
    function updateMaxPoolDailyLendingRateInBPS(uint256 maxPoolDailyLendingRateInBPS) external;

    /**
     * @notice Update the minimal deposit at creation
     * @param minimalDepositAtCreation Minimal deposit at creation
     */
    function updateMinimalDepositAtCreation(uint256 minimalDepositAtCreation) external;

    /**
     * @notice Update the pool implementation address
     * @param poolImplementation Pool implementation address
     */
    function updatePoolImplementation(address poolImplementation) external;

    /**
     * @notice Update the protocol fee collector address
     * @param protocolFeeCollector Protocol fee collector address
     */
    function updateProtocolFeeCollector(address protocolFeeCollector) external;

    /**
     * @notice Upgrade Proxy of the factory
     * @param newImplementation New implementation contract
     * @param data Optional calldata
     */
    function upgradeToAndCall(address newImplementation, bytes calldata data) external;
}
