// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface ICollateralLiquidator {
    function liquidate(
        address collateralToken,
        uint256 collateralTokenId,
        uint256 startingPrice,
        address borrower
    ) external;

    function liquidationDuration() external view returns (uint256);
}
