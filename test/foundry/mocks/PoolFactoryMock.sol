// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {PoolFactory} from "../../../contracts/PoolFactory.sol";

contract PoolFactoryMock is PoolFactory {
    /* override initialize so that we can initialise it again */
    function initialize(
        address factoryOwner_,
        address protocolFeeCollector_,
        uint256 minimalDepositAtCreation_,
        uint256 maxPoolDailyInterestRate_
    ) external override {
        require(factoryOwner_ != address(0), "PoolFactory: Factory owner cannot be zero address");
        require(
            protocolFeeCollector_ != address(0),
            "PoolFactory: Protocol fee collector cannot be zero address"
        );
        _transferOwnership(factoryOwner_);
        protocolFeeCollector = protocolFeeCollector_;
        minimalDepositAtCreation = minimalDepositAtCreation_;
        maxPoolDailyInterestRate = maxPoolDailyInterestRate_;
    }
}
