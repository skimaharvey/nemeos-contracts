// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPool {
    function initialize(
        address nftCollection_,
        address asset_,
        uint256 loanToValueinBPS_,
        uint256 initialDailyInterestRateinBPS_,
        address wrappedNFT_,
        address liquidator_,
        address NFTFilter_,
        address protocolFeeCollector_
    ) external;

    function refundFromLiquidation(uint256 tokenId) external payable;

    function ltvInBPS() external view returns (uint256);
}
