// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ICollateralWrapper {
    function burn(uint256 tokenId) external;

    function mint(uint256 tokenId, address receiver) external;
}
