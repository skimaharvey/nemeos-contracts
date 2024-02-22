// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import {IDutchAuctionLiquidator} from "../interfaces/IDutchAuctionLiquidator.sol";

contract PoolMock {
    event LoanLiquidationRefund(address indexed token, uint256 indexed tokenId, uint256 amount);

    address public liquidator;
    address public collectionAddress;

    constructor(address liquidator_, address collectionAddress_) {
        liquidator = liquidator_;
        collectionAddress = collectionAddress_;
    }

    function liquidateLoan(uint256 tokenId_, address borrower_) external {
        IDutchAuctionLiquidator(liquidator).liquidate(
            collectionAddress,
            tokenId_,
            1 ether,
            borrower_
        );
    }

    function refundFromLiquidation(uint256 tokenId_, address borrower_) external payable {
        emit LoanLiquidationRefund(address(this), tokenId_, msg.value);
    }
}
