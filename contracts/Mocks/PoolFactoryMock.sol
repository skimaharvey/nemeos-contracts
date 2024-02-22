// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {INFTWrapper} from "../interfaces/INFTWrapper.sol";
import {INFTWrapperFactory} from "..//interfaces/INFTWrapperFactory.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract PoolFactoryMock {
    address[] public pools;
    address public NFTWrapperFactory;
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

    function addPoolToNFTWrapperFactory(address NFTWrapper_, address pool_) external {
        INFTWrapper(NFTWrapper_).addPool(pool_);
    }

    function createPool(
        address collection_,
        address /* assets_ */,
        uint256 /* minimalDepositInBPS_ */,
        uint256 /* initialDailyInterestRateInBPS_ */,
        uint256 /* initialDeposit_ */,
        address /* nftFilter_ */,
        address /* liquidator_ */
    ) external payable returns (address, address) {
        address NFTWrapper = INFTWrapperFactory(NFTWrapperFactory).deployNFTWrapper(collection_);
        address poolInstance = Clones.clone(poolImplementation);

        return (poolInstance, NFTWrapper);
    }

    function updateNFTWrapperFactory(address newNFTFactory) external {
        NFTWrapperFactory = newNFTFactory;
    }
}
