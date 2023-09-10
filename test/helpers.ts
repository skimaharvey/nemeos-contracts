import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { Pool, SeaportSettlementManager } from '../typechain-types';
import { expect } from 'chai';

import OfferData from './fullfil-offer-data.json';

export async function mockSignLoan(
  collecttionAddress: string,
  tokenId: string,
  price: BigNumber,
  priceWithFees: BigNumber,
  customerAddress: string,
  nonce: number,
  loanTimestamp: number,
  orderExtraData: string,
  oracleSigner: SignerWithAddress,
) {
  const chainId = (await ethers.provider.getNetwork()).chainId;

  const dataToEncode = ethers.utils.solidityPack(
    [
      'uint256',
      'address',
      'uint256',
      'uint256',
      'uint256',
      'address',
      'uint256',
      'uint256',
      'bytes',
    ],
    [
      chainId,
      collecttionAddress,
      tokenId,
      price,
      priceWithFees,
      customerAddress,
      nonce,
      loanTimestamp,
      orderExtraData,
    ],
  );
  const messageHash = ethers.utils.solidityKeccak256(['bytes'], [dataToEncode]);

  return await oracleSigner.signMessage(ethers.utils.arrayify(messageHash));
}

export async function buyNFTPreparationHelper() {
  const nftPrice = OfferData.fulfillment_data.transaction.value;

  // get block timestamp
  const block = await ethers.provider.getBlock('latest');
  const loanTimestamp = block.timestamp;

  const {
    considerationToken,
    considerationIdentifier,
    considerationAmount,
    offerer,
    zone,
    offerAmount,
    basicOrderType,
    startTime,
    endTime,
    zoneHash,
    salt,
    offererConduitKey,
    fulfillerConduitKey,
    totalOriginalAdditionalRecipients,
    signature,
    offerIdentifier: tokenId,
  } = OfferData.fulfillment_data.transaction.input_data.parameters;

  const additionalRecipientsArray =
    OfferData.fulfillment_data.transaction.input_data.parameters.additionalRecipients.map(
      ({ amount, recipient }) => [amount, recipient],
    );

  const orderExtraDataTypes = [
    'address', // considerationToken
    'uint256', // considerationIdentifier
    'uint256', // considerationAmount
    'address', // offerer
    'address', // zone
    'uint256', // offerAmount
    'uint256', // basicOrderType
    'uint256', // startTime
    'uint256', // endTime
    'bytes32', // zoneHash
    'uint256', // salt
    'bytes32', // offererConduitKey
    'bytes32', // fulfillerConduitKey
    'uint256', // totalOriginalAdditionalRecipients
    'tuple(uint256,address)[]', // additionalRecipients
    'bytes', // signature
  ];

  const orderExtraDataValues = [
    considerationToken,
    considerationIdentifier,
    considerationAmount,
    offerer,
    zone,
    offerAmount,
    basicOrderType,
    startTime,
    endTime,
    zoneHash,
    salt,
    offererConduitKey,
    fulfillerConduitKey,
    totalOriginalAdditionalRecipients,
    additionalRecipientsArray,
    signature,
  ];

  const orderExtraData = ethers.utils.defaultAbiCoder.encode(
    orderExtraDataTypes,
    orderExtraDataValues,
  );

  return {
    tokenId,
    orderExtraData,
    loanTimestamp,
    nftPrice,
  };
}

export async function buyNFTHelper(
  poolProxy: Pool,
  borrower: SignerWithAddress,
  collecttionAddress: string,
  offerIdentifier: string,
  nftPrice: BigNumber,
  priceWithInterest: BigNumber,
  seaportSettlementManager: SeaportSettlementManager,
  loanTimestamp: number,
  loanDurationInSeconds: number,
  orderExtraData: string,
  oracleSignature: string,
  ltvValue: BigNumber,
) {
  const tx = await poolProxy
    .connect(borrower)
    .buyNFT(
      collecttionAddress,
      offerIdentifier,
      nftPrice,
      priceWithInterest,
      seaportSettlementManager.address,
      loanTimestamp,
      loanDurationInSeconds,
      orderExtraData,
      oracleSignature,
      { value: ltvValue },
    );

  await expect(tx).to.emit(seaportSettlementManager, 'BuyExecuted');
}
