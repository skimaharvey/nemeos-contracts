import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

export async function mockSignLoan(
  collecttionAddress: string,
  tokenId: string,
  price: BigNumber,
  customerAddress: string,
  nonce: number,
  loanTimestamp: number,
  orderExtraData: string,
  oracleSigner: SignerWithAddress,
) {
  const chainId = (await ethers.provider.getNetwork()).chainId;

  const dataToEncode = ethers.utils.solidityPack(
    ['uint256', 'address', 'uint256', 'uint256', 'address', 'uint256', 'uint256', 'bytes'],
    [
      chainId,
      collecttionAddress,
      tokenId,
      price,
      customerAddress,
      nonce,
      loanTimestamp,
      orderExtraData,
    ],
  );
  const messageHash = ethers.utils.solidityKeccak256(['bytes'], [dataToEncode]);

  return await oracleSigner.signMessage(ethers.utils.arrayify(messageHash));
}
