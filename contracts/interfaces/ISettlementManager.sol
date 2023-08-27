// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISettlementManager {
    function executeBuy(
        address collectionAddress,
        uint256 tokenId,
        bytes calldata orderExtraData
    ) external payable;
}
