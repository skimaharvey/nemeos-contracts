// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface INFTWrapperFactory {
    /**************************************************************************/
    /* Events */
    /**************************************************************************/

    /**
     * @notice Emitted when a new nft wrapper is created
     * @param collection Address of the collection
     * @param NFTWrapper Address of the new nft wrapper
     */
    event NFTWrapperCreated(address indexed collection, address indexed NFTWrapper);

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/

    /**
     * @notice Deploy a new NFT wrapper
     * @param collection Address of the collection
     * @return NFTWrapperAddress Address of the new NFT wrapper
     */
    function deployNFTWrapper(address collection) external returns (address NFTWrapperAddress);

    /**
     * @notice Get the NFT implementation contract address
     * @return NFT implementation contract address
     */
    function nftImplementationContract() external view returns (address);

    /**
     * @notice Get the NFT wrapper address of a collection
     * @param collection Address of the collection
     * @return NFTWrapperAddress Address of the NFT wrapper
     */
    function nftWrappers(address collection) external view returns (address);

    /**
     * @notice Get the pool factory address
     * @return Pool factory address
     */
    function poolFactory() external view returns (address);
}
