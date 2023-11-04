// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {NFTFilter} from "../../../contracts/NFTFilter.sol";

contract NFTFilterMock is NFTFilter {
    constructor(
        address oracle_,
        address protocolAdmin_,
        address[] memory supportedSettlementManagers_
    ) NFTFilter(oracle_, protocolAdmin_, supportedSettlementManagers_) {}

    /* override verifyLoanValidity so that it returns true*/
    function verifyLoanValidity(
        address,
        uint256,
        uint256,
        uint256,
        address,
        address,
        uint256,
        bytes calldata,
        bytes memory
    ) external override returns (bool isValid) {
        return true;
    }
}
