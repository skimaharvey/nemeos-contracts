// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ICollateralLiquidator {
    function liquidate(
        address collateralToken_,
        uint256 collateralTokenId_,
        uint256 startingPrice_
    ) external;
}
