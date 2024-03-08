// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

// libraries
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// interfaces
import {INFTFilter} from "./interfaces/INFTFilter.sol";
import {IPoolFactory} from "./interfaces/IPoolFactory.sol";

/**
 * @title NFTFilter
 * @author Nemeos
 */
contract NFTFilter is INFTFilter {
    using ECDSA for *;
    /**************************************************************************/
    /* State */
    /**************************************************************************/

    /**
     * @dev see {INFTFilter-LOAN_EXPIRATION_TIME}
     */
    uint256 public constant LOAN_EXPIRATION_TIME = 3 minutes;

    /**
     * @notice Supported settlement managers addresses
     */
    address[] public supportedSettlementManagers;

    /**
     * @dev see {INFTFilter-oracle}
     */
    address public oracle;

    /**
     * @dev see {INFTFilter-poolFactory}
     */
    address public immutable poolFactory;

    /**
     * @dev see {INFTFilter-protocolAdmin}
     */
    address public immutable protocolAdmin;

    /**
     * @dev see {INFTFilter-customerNonces}
     */
    mapping(address => uint256) public customerNonces;

    /**************************************************************************/
    /* Constructor */
    /**************************************************************************/

    constructor(
        address oracle_,
        address protocolAdmin_,
        address[] memory supportedSettlementManagers_,
        address poolFactory_
    ) {
        oracle = oracle_;
        protocolAdmin = protocolAdmin_;
        supportedSettlementManagers = supportedSettlementManagers_;
        poolFactory = poolFactory_;
    }

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/

    /*
     * @dev see {INFTFilter-getSupportedSettlementManagers}
     */
    function getSupportedSettlementManagers() external view returns (address[] memory) {
        return supportedSettlementManagers;
    }

    /*
     * @dev see {INFTFilter-verifyLoanValidity}
     */
    function verifyLoanValidity(
        uint256 nftID_,
        uint256 priceOfNFT_,
        uint256 nftFloorPrice_,
        uint256 priceIncludingFees_,
        address customerAddress_,
        address settlementManager_,
        uint256 loanTimestamp_,
        bytes calldata orderExtraData_,
        bytes memory signature
    ) external virtual returns (bool isValid) {
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

        require(IPoolFactory(poolFactory).isPool(msg.sender), "NFTFilter: Caller is not a pool");

        /* get customer nonce and increase it by one*/
        uint256 nonce = customerNonces[customerAddress_]++;

        bytes32 encodedMessageHash = ECDSA.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    block.chainid,
                    msg.sender,
                    nftID_,
                    priceOfNFT_,
                    nftFloorPrice_,
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
            msg.sender, // pool
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

    /*
     * @dev see {INFTFilter-updateOracle}
     */
    function updateOracle(address oracle_) external {
        require(msg.sender == protocolAdmin, "NFTFilter: Only protocol admin can update oracle");
        oracle = oracle_;

        emit OracleUpdated(oracle);
    }

    /*
     * @dev see {INFTFilter-updatesupportedSettlementManagers}
     */
    function updatesupportedSettlementManagers(
        address[] memory supportedSettlementManagers_
    ) external {
        require(
            msg.sender == protocolAdmin,
            "NFTFilter: Only protocol admin can update supportedSettlementManagers"
        );
        supportedSettlementManagers = supportedSettlementManagers_;

        emit SupportedSettlementManagersUpdated(supportedSettlementManagers);
    }
}
