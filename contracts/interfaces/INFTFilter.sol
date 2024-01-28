// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface INFTFilter {
    /**************************************************************************/
    /* Events */
    /**************************************************************************/

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

    /**
     * @notice Emitted when the oracle address is updated
     * @param oracle New oracle address
     */
    event OracleUpdated(address oracle);

    /**
     * @notice Emitted when the supported settlement managers are updated
     * @param supportedSettlementManagers New supported settlement managers
     */
    event SupportedSettlementManagersUpdated(address[] supportedSettlementManagers);

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/

    /**
     * @notice Get the customer nonce
     * @return customerNonces Customer nonce
     */
    function customerNonces(address) external view returns (uint256);

    /**
     * @notice Get the Supported settlement managers
     * @return the supported settlement managers
     */
    function getSupportedSettlementManagers() external view returns (address[] memory);

    /**
     * @notice Get the loan expiration time
     * @return LOAN_EXPIRATION_TIME Loan expiration time
     */
    function LOAN_EXPIRATION_TIME() external view returns (uint256);

    /**
     * @notice Get the oracle address
     * @return oracle Oracle address
     */
    function oracle() external view returns (address);

    /**
     * @notice Get the protocol admin address
     * @return protocolAdmin Protocol admin address
     */
    function protocolAdmin() external view returns (address);

    /**
     * @notice Update the oracle address
     * @param oracle_ New oracle address
     */
    function updateOracle(address oracle_) external;

    /**
     * @notice Update the supported settlement managers
     * @param supportedSettlementManagers_ New supported settlement managers
     */
    function updatesupportedSettlementManagers(
        address[] memory supportedSettlementManagers_
    ) external;

    /**
     * @notice Verify the validity of a loan
     * @param collectionAddress_ Address of the collection
     * @param nftID_ ID of the NFT
     * @param priceOfNFT_ Price of the NFT
     * @param nftFloorPrice_ Floor price of the NFT
     * @param priceIncludingFees_ Price of the NFT including the interest rate and protocol fees
     * @param customerAddress_ Address of the customer
     * @param settlementManager_ Address of the settlement manager
     * @param loanTimestamp_ Timestamp of the loan
     * @param orderExtraData_ Extra data of the order
     * @param signature Signature of the order
     * @return isValid True if the loan is valid
     */
    function verifyLoanValidity(
        address collectionAddress_,
        uint256 nftID_,
        uint256 priceOfNFT_,
        uint256 nftFloorPrice_,
        uint256 priceIncludingFees_,
        address customerAddress_,
        address settlementManager_,
        uint256 loanTimestamp_,
        bytes calldata orderExtraData_,
        bytes memory signature
    ) external returns (bool isValid);
}
