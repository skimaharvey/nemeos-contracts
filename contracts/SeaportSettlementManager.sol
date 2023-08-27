// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// libraries
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {
    ConsiderationInterface as ISeaport
} from "../lib/seaport/contracts/interfaces/ConsiderationInterface.sol";
import {
    BasicOrderParameters,
    BasicOrderType,
    AdditionalRecipient
} from "../lib/seaport/contracts/lib/ConsiderationStructs.sol";

/**
 * @title SeaportSettlementManager
 * @author Nemeos
 */
contract SeaportSettlementManager {
    /**************************************************************************/
    /* Structs */
    /**************************************************************************/

    struct PartialBasicOrderParameters {
        address considerationToken;
        uint256 considerationIdentifier;
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
    /* Constants */
    /**************************************************************************/

    /**
     * @notice Seaport contract address (V1.5)
     */
    ISeaport public constant SEAPORT = ISeaport(0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC);

    /**************************************************************************/
    /* Implementation */
    /**************************************************************************/

    /**
     * @notice Executes a buy order on the seaport contract
     * @param collectionAddress_ Address of the collection
     * @param tokenId_ ID of the token
     * @param orderExtraData_ Extra params for the seaport contract
     */
    function executeBuy(
        address collectionAddress_,
        uint256 tokenId_,
        bytes calldata orderExtraData_
    ) external payable {
        /**  orderExtraData_ is the encoded BasicOrderParameters struct minus the collectionAddress_ & tokenId_ :
         * address considerationToken,
         * uint256 considerationIdentifier,
         * address offerer
         * address zone
         * address offerToken
         * uint256 offerAmount
         * uint256 offerIdentifier
         * BasicOrderType basicOrderType
         * uint256 startTime
         * uint256 endTime
         * bytes32 zoneHash
         * uint256 salt
         * bytes32 offererConduitKey
         * uint256 totalOriginalAdditionalRecipients
         * AdditionalRecipient[] additionalRecipients
         * bytes signature
         */

        PartialBasicOrderParameters memory partialBasicOrderParameters = abi.decode(
            orderExtraData_,
            (PartialBasicOrderParameters)
        );

        BasicOrderParameters memory buyParams = BasicOrderParameters(
            partialBasicOrderParameters.considerationToken,
            partialBasicOrderParameters.considerationIdentifier,
            msg.value,
            partialBasicOrderParameters.offerer,
            partialBasicOrderParameters.zone,
            collectionAddress_,
            partialBasicOrderParameters.offerAmount,
            tokenId_,
            partialBasicOrderParameters.basicOrderType,
            partialBasicOrderParameters.startTime,
            partialBasicOrderParameters.endTime,
            partialBasicOrderParameters.zoneHash,
            partialBasicOrderParameters.salt,
            partialBasicOrderParameters.offererConduitKey,
            partialBasicOrderParameters.fulfillerConduitKey,
            partialBasicOrderParameters.totalOriginalAdditionalRecipients,
            partialBasicOrderParameters.additionalRecipients,
            partialBasicOrderParameters.signature
        );

        // // TODO: investigate Seaport execution as this might be wrong. params receiver should be the pool address
        // // need to check what happens when sending too much value and possibly refund the pool
        SEAPORT.fulfillBasicOrder{value: msg.value}(buyParams);

        /* transfer NFT to pool */
        IERC721(collectionAddress_).safeTransferFrom(address(this), msg.sender, tokenId_);
    }
}
