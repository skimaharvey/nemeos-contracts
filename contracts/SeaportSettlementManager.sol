// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {
    ConsiderationInterface as ISeaport
} from "../lib/seaport/contracts/interfaces/ConsiderationInterface.sol";
import {BasicOrderParameters} from "../lib/seaport/contracts/lib/ConsiderationStructs.sol";

contract SeaportSettlementManager {
    ISeaport public immutable SEAPORT;

    constructor() {
        SEAPORT = ISeaport(0x00000000000001ad428e4906aE43D8F9852d0dD6);
    }

    function encode(
        BasicOrderParameters calldata _basicOrderParams
    ) external pure returns (bytes memory) {
        return abi.encode(_basicOrderParams);
    }

    function executeBuy(bytes memory _order, uint256 _price) external {
        BasicOrderParameters memory params = abi.decode(_order, (BasicOrderParameters));
        SEAPORT.fulfillBasicOrder{value: _price}(params);

        //emit NFTPAID();
    }

    function transferTo(address _contractAddress, uint256 _tokenId, address _wrappedNFT) external {
        address from = IERC721(_contractAddress).ownerOf(_tokenId);
        IERC721(_contractAddress).safeTransferFrom(from, _wrappedNFT, _tokenId);
    }
}
