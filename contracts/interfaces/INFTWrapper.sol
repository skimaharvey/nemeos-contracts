// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface INFTWrapper {
  /**************************************************************************/
  /* Events */
  /**************************************************************************/

  /**
   * @notice Emitted when a pool is added
   * @param pool Address of the pool
   */
  event AddPool(address pool);

  /**
   * @notice Emitted when the NFT is unwrapped
   * @param tokenId Token ID of the NFT wrapped token
   * @param account Address that unwrapped the NFT
   */
  event NFTBurnt(uint256 indexed tokenId, address indexed account);

  /**
   * @notice Emitted when NFT is minted
   * @param tokenId Token ID of the new NFT wrapped token
   * @param account Address that created the NFT
   */
  event NFTMinted(uint256 indexed tokenId, address indexed account);

  /**************************************************************************/
  /* Implementation */
  /**************************************************************************/

  /**
   * @notice Add pool
   * @dev Only pool factory can call
   * @param pool Pool address
   */

  function addPool(address pool) external;

  /**
   * @notice Burn NFT
   * @dev Only pool can call
   * @param tokenId NFT token ID
   */
  function burn(uint256 tokenId) external;

  /**
   * @notice Get the collection address
   * @return Collection address
   */
  function collection() external view returns (address);

  /**
   * @notice Check if token ID exists
   * @param tokenId Token ID
   * @return True if token ID exists, otherwise false
   */
  function exists(uint256 tokenId) external view returns (bool);

  /**
   * @notice Check if pool exists
   * @param pool Pool address
   * @return True if pool exists, otherwise false
   */
  function existsInPools(address pool) external view returns (bool);

  /**
   * @notice Initialize NFT wrapper
   * @param collection Collection address
   * @param poolFactory Pool factory address
   */
  function initialize(address collection, address poolFactory) external;

  /**
   * @notice Mint Wrapped NFT
   * @dev Only pool can call
   * @param tokenId NFT token IDs
   * @param receiver Address that receives the NFT
   */
  function mint(uint256 tokenId, address receiver) external returns (uint256);

  /**
   * @notice Get the pool factory address
   * @return Pool factory address
   */
  function poolFactory() external view returns (address);

  /**
   * @notice Get the pools
   * @return List of pool addresses
   */
  function pools() external view returns (address[] memory);
}
