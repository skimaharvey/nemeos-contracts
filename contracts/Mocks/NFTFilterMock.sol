// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {NFTFilter} from "../NFTFilter.sol";

contract NFTFilterMock is NFTFilter {
    constructor(
        address oracle_,
        address protocolAdmin_,
        address[] memory supportedSettlementManagers_,
        address poolFactory_
    ) NFTFilter(oracle_, protocolAdmin_, supportedSettlementManagers_, poolFactory_) {}

    /* override verifyLoanValidity so that it returns true*/
    function verifyLoanValidity(
        uint256,
        uint256,
        uint256,
        uint256 ,
        address ,
        address ,
        uint256 ,
        bytes calldata,
        bytes memory 
    ) external override returns (bool isValid) {
        return true;
    }
}
