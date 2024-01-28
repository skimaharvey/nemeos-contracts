// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

// interfaces
import {ISettlementManager} from "./interfaces/ISettlementManager.sol";

// libraries
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {
    ConsiderationInterface as ISeaport
} from "../lib/seaport/contracts/interfaces/ConsiderationInterface.sol";
import {
    BasicOrderParameters,
    AdditionalRecipient
} from "../lib/seaport/contracts/lib/ConsiderationStructs.sol";

/**
 * @title SeaportSettlementManager
 * @author Nemeos
 */
contract SeaportSettlementManager is ISettlementManager {
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
     * @dev see {ISeaportSettlementManager-executeBuy}
     */
    function executeBuy(
        address collectionAddress_,
        uint256 tokenId_,
        bytes calldata orderExtraData_
    ) external payable {
        /**  orderExtraData_ is the encoded BasicOrderParameters struct minus the collectionAddress_ & tokenId_ :
         * address considerationToken
         * uint256 considerationIdentifier
         * uint256 considerationAmount
         * address offerer
         * address zone
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

        BasicOrderParameters memory buyParams = BasicOrderParameters({
            considerationToken: partialBasicOrderParameters.considerationToken,
            considerationIdentifier: partialBasicOrderParameters.considerationIdentifier,
            considerationAmount: partialBasicOrderParameters.considerationAmount,
            offerer: partialBasicOrderParameters.offerer,
            zone: partialBasicOrderParameters.zone,
            offerToken: collectionAddress_,
            offerIdentifier: tokenId_,
            offerAmount: partialBasicOrderParameters.offerAmount,
            basicOrderType: partialBasicOrderParameters.basicOrderType,
            startTime: partialBasicOrderParameters.startTime,
            endTime: partialBasicOrderParameters.endTime,
            zoneHash: partialBasicOrderParameters.zoneHash,
            salt: partialBasicOrderParameters.salt,
            offererConduitKey: partialBasicOrderParameters.offererConduitKey,
            fulfillerConduitKey: partialBasicOrderParameters.fulfillerConduitKey,
            totalOriginalAdditionalRecipients: partialBasicOrderParameters
                .totalOriginalAdditionalRecipients,
            additionalRecipients: partialBasicOrderParameters.additionalRecipients,
            signature: partialBasicOrderParameters.signature
        });

        /* execute buy order */
        SEAPORT.fulfillBasicOrder{value: msg.value}(buyParams);

        /* emit BuyExecuted event */
        emit BuyExecuted(collectionAddress_, tokenId_, msg.sender, msg.value);

        /* transfer NFT to pool todo: use safeTransferFrom with recipient hook*/
        IERC721(collectionAddress_).transferFrom(address(this), msg.sender, tokenId_);
    }
}
