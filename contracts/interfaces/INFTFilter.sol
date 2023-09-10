// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface INFTFilter {
    function verifyLoanValidity(
        address collectionAddress,
        uint256 nftID,
        uint256 price,
        uint256 priceIncludingFees_,
        address customerAddress,
        address marketplaceAddress,
        uint256 loanTimestamp,
        bytes memory orderExtraData,
        bytes memory signature
    ) external returns (bool isValid);
}
