// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

abstract contract Constants {
    uint256 internal constant minimalDepositAtCreation = 1 ether;
    uint64 internal constant liquidationDurationInDays = 7;
    uint256 internal ltvInBPS = 1000; // 10%
    uint256 internal initialDailyRateInBPS = 10; // 0.1%
    uint40 internal constant MAY_1_2023 = 1_682_899_200;
}
