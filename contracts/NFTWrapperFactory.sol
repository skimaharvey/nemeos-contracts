// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// interfaces
import {INFTWrapperFactory} from "./interfaces/INFTWrapperFactory.sol";

// contract
import {NFTWrapper} from "./NFTWrapper.sol";

// libraries
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title NFTWrapperFactory
 * @author Nemeos
 * @notice Factory for NFT wrappers
 */
contract NFTWrapperFactory is INFTWrapperFactory {
    /**************************************************************************/
    /* State */
    /**************************************************************************/

    /**
     * @dev see {INFTWrapperFactory-poolFactory}
     */
    address public immutable poolFactory;

    /**
     * @dev see {INFTWrapperFactory-nftImplementationContract}
     */
    address public immutable nftImplementationContract = address(new NFTWrapper());

    /**
     * @dev see {INFTWrapperFactory-nftWrappers}
     */
    mapping(address => address) public nftWrappers;

    /**************************************************************************/
    /* Constructor */
    /**************************************************************************/

    constructor(address poolFactory_) {
        poolFactory = poolFactory_;
    }

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/

    /**
     * @dev see {INFTWrapperFactory-deployNFTWrapper}
     */
    function deployNFTWrapper(address collection_) external returns (address NFTWrapperAddress) {
        /* Only allow PoolFactory to call */
        require(msg.sender == poolFactory, "NFTWrapper: Only pool factory can call");

        /* Check if NFT wrapper already exists */
        require(nftWrappers[collection_] == address(0), "NFTWrapper: NFT wrapper already exists");

        /* Deploy NFT wrapper */
        NFTWrapperAddress = Clones.clone(nftImplementationContract);

        /* Initialize NFT wrapper */
        NFTWrapper(NFTWrapperAddress).initialize(collection_, poolFactory);

        /* Update NFTWrapper mapping to avoid deploying twice the  */
        nftWrappers[collection_] = NFTWrapperAddress;

        /* Emit event */
        emit NFTWrapperCreated(collection_, NFTWrapperAddress);
    }
}
