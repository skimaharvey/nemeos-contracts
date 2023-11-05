// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

struct Users {
    // Default admin for factory proxy.
    address payable factoryProxyAdmin;
    // Default admin for all Nemeos contracts.
    address payable admin;
    // Impartial user.
    address payable alice;
    // Malicious user.
    address payable eve;
    // Default Factory owner.
    address payable factoryOwner;
    // Default oracle for the NFTFilter.
    address payable oracle;
    // Defaut Protocol fee collector.
    address payable protocolFeeCollector;
    // Default stream recipient.
    address payable recipient;
    // Default stream sender.
    address payable sender;
}
