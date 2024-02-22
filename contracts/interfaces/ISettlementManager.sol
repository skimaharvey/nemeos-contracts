// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {
    BasicOrderType,
    AdditionalRecipient
} from "../../lib/seaport/contracts/lib/ConsiderationStructs.sol";
import {
    ConsiderationInterface as ISeaport
} from "../../lib/seaport/contracts/interfaces/ConsiderationInterface.sol";

interface ISettlementManager {
    /**************************************************************************/
    /* Events */
    /**************************************************************************/
    event BuyExecuted(
        address indexed collectionAddress,
        uint256 indexed tokenId,
        address indexed pool,
        uint256 amount
    );

    /**************************************************************************/
    /* Structs */
    /**************************************************************************/

    struct PartialBasicOrderParameters {
        address considerationToken;
        uint256 considerationIdentifier;
        uint256 considerationAmount;
        address payable offerer;
        address zone;
        uint256 offerAmount;
        BasicOrderType basicOrderType;
        uint256 startTime;
        uint256 endTime;
        bytes32 zoneHash;
        uint256 salt;
        bytes32 offererConduitKey;
        bytes32 fulfillerConduitKey;
        uint256 totalOriginalAdditionalRecipients;
        AdditionalRecipient[] additionalRecipients;
        bytes signature;
    }

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/

    /**
     * @notice Executes a buy order on the seaport contract
     * @param collectionAddress Address of the collection
     * @param tokenId ID of the token
     * @param orderExtraData Extra params for the seaport contract
     */
    function executeBuy(
        address collectionAddress,
        uint256 tokenId,
        bytes calldata orderExtraData
    ) external payable;

    /**
     * @notice Get the seaport contract interface
     * @return Seaport contract interface
     */
    function SEAPORT() external view returns (ISeaport);
}
