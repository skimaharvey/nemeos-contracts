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
     * @notice Supported settlement managers addresses
     */
    address[] public supportedSettlementManagers;

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
     * @notice Emitted when the supported settlement managers are updated
     * @param supportedSettlementManagers New supported settlement managers
     */
    event supportedSettlementManagersUpdated(address[] supportedSettlementManagers);

    /**
     * @notice Emitted when a loan is verified
     * @param collectionAddress_ Address of the collection
     * @param nftID_ ID of the NFT
     * @param priceOfNFT_ Price of the NFT
     * @param priceIncludingFees_ Price of the NFT including the interest rate and protocol fees
     * @param customerAddress_ Address of the customer
     * @param settlementManager_ Address of the settlement manager
     * @param loanTimestamp_ Timestamp of the loan
     */
    event LoanVerified(
        address collectionAddress_,
        uint256 nftID_,
        uint256 priceOfNFT_,
        uint256 priceIncludingFees_,
        address customerAddress_,
        address settlementManager_,
        uint256 loanTimestamp_
    );

    /**************************************************************************/
    /* Constructor */
    /**************************************************************************/

    constructor(
        address oracle_,
        address protocolAdmin_,
        address[] memory supportedSettlementManagers_
    ) {
        oracle = oracle_;
        protocolAdmin = protocolAdmin_;
        supportedSettlementManagers = supportedSettlementManagers_;
    }

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/

    function verifyLoanValidity(
        address collectionAddress_,
        uint256 nftID_,
        uint256 priceOfNFT_,
        uint256 priceIncludingFees_,
        address customerAddress_,
        address settlementManager_,
        uint256 loanTimestamp_,
        bytes calldata orderExtraData_,
        bytes memory signature
    ) external returns (bool isValid) {
        /* check that loan is not expired */
        require(block.timestamp < loanTimestamp_ + LOAN_EXPIRATION_TIME, "NFTFilter: Loan expired");

        /* check that settlement manager is supported */
        bool isSupportedSettlementManager;
        for (uint256 i = 0; i < supportedSettlementManagers.length; i++) {
            if (supportedSettlementManagers[i] == settlementManager_) {
                isSupportedSettlementManager = true;
                break;
            }
        }
        require(isSupportedSettlementManager, "NFTFilter: Settlement Manager not supported");

        /* get customer nonce and increase it by one*/
        uint256 nonce = customerNonces[customerAddress_]++;

        bytes32 encodedMessageHash = ECDSA.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    block.chainid,
                    collectionAddress_,
                    nftID_,
                    priceOfNFT_,
                    priceIncludingFees_,
                    customerAddress_,
                    nonce,
                    loanTimestamp_,
                    orderExtraData_
                )
            )
        );

        /* check that the signature is valid */
        address signer = ECDSA.recover(encodedMessageHash, signature);

        /* check that the signer is the oracle */
        isValid = signer == oracle;

        /* emit event */
        emit LoanVerified(
            collectionAddress_,
            nftID_,
            priceOfNFT_,
            priceIncludingFees_,
            customerAddress_,
            settlementManager_,
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
     * @notice Update the supported settlement managers
     * @param supportedSettlementManagers_ New supported settlement managers
     */
    function updatesupportedSettlementManagers(
        address[] memory supportedSettlementManagers_
    ) external {
        require(
            msg.sender == protocolAdmin,
            "NFTFilter: Only protocol admin can update supportedSettlementManagers"
        );
        supportedSettlementManagers = supportedSettlementManagers_;

        emit supportedSettlementManagersUpdated(supportedSettlementManagers);
    }
}
