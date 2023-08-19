// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPool {
    function initialize(
        address collection,
        uint256 ltv,
        address collateralWrapper,
        address liquidator
    ) external;

    function refundFromLiquidation(uint256 tokenId) external payable;
}
