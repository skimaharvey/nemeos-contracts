// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPool {
    function initialize(
        address asset,
        uint256 loanToValueinBPS,
        uint256 initialDailyInterestRateinBPS,
        address wrappedNFT,
        address liquidator,
        address NFTFilter,
        address protocolFeeCollector,
        string memory name,
        string memory symbol
    ) external;

    function refundFromLiquidation(uint256 tokenId) external payable;
}
