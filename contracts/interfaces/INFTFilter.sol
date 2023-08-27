// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface INFTFilter {
    function verifyLoanValidity(
        address collectionAddress_,
        uint256 nftID_,
        uint256 price_,
        address customerAddress_,
        address marketplaceAddress_,
        uint256 loanTimestamp_,
        bytes memory orderExtraData_,
        bytes memory signature
    ) external returns (bool isValid);
}
