// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {CollateralWrapper} from "../../../contracts/CollateralWrapper.sol";

contract CollateralWrapperMock is CollateralWrapper {
    /* override initialize so that we can initialise it again */
    function initialize(address collection_, address poolFactory_) external override {
        collection = collection_;
        poolFactory = poolFactory_;
    }
}
