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
   * @param ltv Loan to value ratio
   * @param pool Pool address
   * @param deployer Pool deployer address
   */
  event PoolCreated(
    address indexed collection,
    uint256 ltv,
    address indexed pool,
    address indexed deployer
  );

  /**
   * @notice Emitted when the allowed loan to value ratios are updated
   * @param allowedLTVs New allowed loan to value ratios
   */
  event UpdateAllowedLTVs(uint256[] allowedLTVs);

  /**
   * @notice Emitted when the allowed NFT filters are updated
   * @param allowedNFTFilters New allowed NFT filters
   */
  event UpdateAllowedNFTFilters(address[] allowedNFTFilters);

  /**
   * @notice Emitted when the collateral factory is updated
   * @param collateralFactory New collateral factory address
   */
  event UpdateCollateralFactory(address indexed collateralFactory);

  /**
   * @notice Emitted when the minimal deposit at creation is updated
   * @param minimalDepositAtCreation New minimal deposit at creation
   */
  event UpdateMinimalDepositAtCreation(uint256 minimalDepositAtCreation);

  /**
   * @notice Emitted when the pool implementation is updated
   * @param poolImplementation New pool implementation address
   */
  event UpdatePoolImplementation(address indexed poolImplementation);

  /**************************************************************************/
  /* Implementation */
  /**************************************************************************/

  /**
   * Create a 1167 proxy pool instance
   * @param collection Collection address
   * @param ltvInBPS Loan to value ratio
   * @param initialDailyInterestRateInBPS Initial daily interest rate
   * @param nftFilter NFT filter collection address
   * @param liquidator Liquidator address (used to liquidate non paid loans)
   * @return Pool address
   */
  function createPool(
    address collection,
    uint256 ltvInBPS,
    uint256 initialDailyInterestRateInBPS,
    address nftFilter,
    address liquidator
  ) external payable returns (address);

  /**
   * @notice Check if address is a pool
   * @param pool Pool address
   * @return True if address is a pool, otherwise false
   */
  function isPool(address pool) external view returns (bool);

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
   * @notice Get the Pool address by collection and loan to value ratio
   * @return Pool address
   */
  function getPoolByCollectionAndLtv(
    address collection,
    uint256 ltv
  ) external view returns (address);

  /**
   * @notice Get the liquidator address
   * @return Return the liquidator address
   */
  function liquidator() external view returns (address);

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
   * @notice Update the nft wrapper factory address
   * @param nftWrapperFactory NFT Wrapper Factory address
   */
  function updateNftWrapperFactory(address nftWrapperFactory) external;
}
