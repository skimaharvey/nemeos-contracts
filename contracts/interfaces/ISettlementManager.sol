// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISettlementManager {
    function executeBuy(bytes memory _order) external payable;
}
