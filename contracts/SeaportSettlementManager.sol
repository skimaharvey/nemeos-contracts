// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {
    ConsiderationInterface as ISeaport
} from "../lib/seaport/contracts/interfaces/ConsiderationInterface.sol";
import {BasicOrderParameters} from "../lib/seaport/contracts/lib/ConsiderationStructs.sol";

contract SeaportSettlementManager {
    /**************************************************************************/
    /* Constants */
    /**************************************************************************/

    ISeaport public constant SEAPORT = ISeaport(0x00000000000001ad428e4906aE43D8F9852d0dD6);

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/

    /**
     * @notice Executes a buy order on the seaport contract
     * @param _order Order to execute
     */
    function executeBuy(bytes memory _order) external payable {
        BasicOrderParameters memory params = abi.decode(_order, (BasicOrderParameters));
        // TODO: investigate Seaport execution as this might be wrong. params receiver should be the pool address
        // need to check what happens when sending too much value and possibly refund the pool
        SEAPORT.fulfillBasicOrder{value: msg.value}(params);
    }
}
