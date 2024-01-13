// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface IPoolFactory {
    function isPool(address pool) external view returns (bool);
}
