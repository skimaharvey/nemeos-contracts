// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {CollateralFactory} from "../CollateralFactory.sol";
import {CollateralWrapper} from "../CollateralWrapper.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract PoolFactoryMock {
    address[] public pools;
    address public collateralFactory;
    address poolImplementation;

    constructor(address poolImplementation_) {
        poolImplementation = poolImplementation_;
    }

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

    function addPoolToCollateralWrapper(address collateralWrapper, address pool) external {
        CollateralWrapper(collateralWrapper).addPool(pool);
    }

    function createPool(
        address collection_,
        address /* assets_ */,
        uint256 /* ltvInBPS_ */,
        uint256 /* initialDailyInterestRateInBPS_ */,
        uint256 /* initialDeposit_ */,
        address /* nftFilter_ */,
        address /* liquidator_ */
    ) external payable returns (address, address) {
        address collateralWrapper = CollateralFactory(collateralFactory).deployCollateralWrapper(
            collection_
        );
        address poolInstance = Clones.clone(poolImplementation);

        return (poolInstance, collateralWrapper);
    }

    function updateCollateralFactory(address newCollateralFactory) external {
        collateralFactory = newCollateralFactory;
    }
}
