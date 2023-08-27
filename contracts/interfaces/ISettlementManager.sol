// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISettlementManager {
    function executeBuy(
        address collectionAddress_,
        uint256 tokenId_,
        bytes calldata orderExtraData_
    ) external payable;
}
