// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// libraries
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title NFTFilter
 * @author Nemeos
 */
contract NFTFilter {
    using ECDSA for *;
    /**************************************************************************/
    /* State */
    /**************************************************************************/

    /**
     * @notice Loan expiration time
     */
    uint256 constant LOAN_EXPIRATION_TIME = 3 minutes;

    /**
     * @notice Supported marketplaces addresses
     */
    address[] public supportedMarketPlaces;

    /**
     * @notice address of the Oracle
     */
    address public oracle;

    /**
     * @notice address of the protocol admin
     */
    address public protocolAdmin;

    /**
     * @dev A mapping of addresses to a nonce.
     *
     * A nonce is incremented each time a customer starts a loan.
     */
    mapping(address => uint256) customerNonces;

    /**************************************************************************/
    /* Events */
    /**************************************************************************/

    /**
     * @notice Emitted when the oracle address is updated
     * @param oracle New oracle address
     */
    event OracleUpdated(address oracle);

    /**
     * @notice Emitted when the supported marketplaces are updated
     * @param supportedMarketPlaces New supported marketplaces
     */
    event SupportedMarketPlacesUpdated(address[] supportedMarketPlaces);

    /**
     * @notice Emitted when a loan is verified
     * @param collectionAddress_ Address of the collection
     * @param nftID_ ID of the NFT
     * @param price_ Price of the NFT
     * @param customerAddress_ Address of the customer
     * @param marketplaceAddress_ Address of the marketplace
     * @param loanTimestamp_ Timestamp of the loan
     */
    event LoanVerified(
        address collectionAddress_,
        uint256 nftID_,
        uint256 price_,
        address customerAddress_,
        address marketplaceAddress_,
        uint256 loanTimestamp_
    );

    /**************************************************************************/
    /* Constructor */
    /**************************************************************************/

    constructor(address oracle_, address protocolAdmin_, address[] memory supportedMarketPlaces_) {
        oracle = oracle_;
        protocolAdmin = protocolAdmin_;
        supportedMarketPlaces = supportedMarketPlaces_;
    }

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/

    function verifyLoanValidity(
        address collectionAddress_,
        uint256 nftID_,
        uint256 price_,
        address customerAddress_,
        address marketplaceAddress_,
        uint256 loanTimestamp_,
        bytes memory signature
    ) external returns (bool isValid) {
        /* check that loan is not expired */
        require(block.timestamp < loanTimestamp_ + LOAN_EXPIRATION_TIME, "NFTFilter: Loan expired");

        /* check that marketplace is supported */
        bool isSupportedMarketplace;
        for (uint256 i = 0; i < supportedMarketPlaces.length; i++) {
            if (supportedMarketPlaces[i] == marketplaceAddress_) {
                isSupportedMarketplace = true;
                break;
            }
        }
        require(isSupportedMarketplace, "NFTFilter: Marketplace not supported");

        /* get customer nonce and increase it by one*/
        uint256 nonce = customerNonces[customerAddress_]++;

        bytes memory encodedMessage = abi.encodePacked(
            block.chainid,
            collectionAddress_,
            nftID_,
            price_,
            customerAddress_,
            nonce,
            loanTimestamp_
        );

        // todo: check if we will use this address or the pool to verify the signature
        /* check that the signature is valid */
        address signer = address(this).toDataWithIntendedValidatorHash(encodedMessage).recover(
            signature
        );

        /* check that the signer is the oracle */
        isValid = signer == oracle;

        /* emit event */
        emit LoanVerified(
            collectionAddress_,
            nftID_,
            price_,
            customerAddress_,
            marketplaceAddress_,
            loanTimestamp_
        );
    }

    /**************************************************************************/
    /* Admin API */
    /**************************************************************************/

    /**
     * @notice Update the oracle address
     * @param oracle_ New oracle address
     */
    function updateOracle(address oracle_) external {
        require(msg.sender == protocolAdmin, "NFTFilter: Only protocol admin can update oracle");
        oracle = oracle_;

        emit OracleUpdated(oracle);
    }

    /**
     * @notice Update the supported marketplaces
     * @param supportedMarketPlaces_ New supported marketplaces
     */
    function updateSupportedMarketPlaces(address[] memory supportedMarketPlaces_) external {
        require(
            msg.sender == protocolAdmin,
            "NFTFilter: Only protocol admin can update supportedMarketPlaces"
        );
        supportedMarketPlaces = supportedMarketPlaces_;

        emit SupportedMarketPlacesUpdated(supportedMarketPlaces);
    }
}
