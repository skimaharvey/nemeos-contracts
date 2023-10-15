// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {CollateralFactory} from "../CollateralFactory.sol";

contract PoolFactoryMock {
    address[] public pools;
    address public collateralFactory;

    function isPool(address pool) external view returns (bool) {
        // pool length
        uint256 poolsLength = pools.length;
        // loop through pools
        for (uint256 i = 0; i < poolsLength; i++) {
            // if pool is found
            if (pools[i] == pool) {
                // return true
                return true;
            }
        }
        // return false
        return false;
    }

    function addPool(address newPool) external {
        pools.push(newPool);
    }

    function createPool(
        address collection_,
        address /* assets_ */,
        uint256 /* ltvInBPS_ */,
        uint256 /* initialDailyInterestRateInBPS_ */,
        uint256 /* initialDeposit_ */,
        address /* nftFilter_ */,
        address /* liquidator_ */
    ) external payable returns (address) {
        CollateralFactory(collateralFactory).deployCollateralWrapper(collection_);
    }

    function updateCollateralFactory(address newCollateralFactory) external {
        collateralFactory = newCollateralFactory;
    }
}
