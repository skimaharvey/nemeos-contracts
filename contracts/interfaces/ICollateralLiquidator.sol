// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ICollateralLiquidator {
    function liquidate(
        address collateralToken,
        uint256 collateralTokenId,
        uint256 startingPrice
    ) external;
}
