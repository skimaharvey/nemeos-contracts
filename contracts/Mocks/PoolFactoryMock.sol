// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract PoolFactoryMock {
    address[] public pools;

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
}
