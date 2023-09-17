import { ethers } from 'hardhat';

const NFT_FILTER_ADDRESS = '0x90d5e0cd6E36E274Ed801F1b5a01Af0f2e379D10';
const ALLOWED_SETTLEMENT_MANAGERS = [
  '0xC385568955b1434207bbC598026Da0d145aC7436',
  '0x9B213ca33427697D7D5FD3e3d7b6377b673168DD',
  '0x8578808D6C5d2BE3396dfA647B661D56119F7cec', // latest seaport settler
];

async function main() {
  const poolFactory = await ethers.getContractAt('NFTFilter', NFT_FILTER_ADDRESS);
  const tx = await poolFactory.updatesupportedSettlementManagers(ALLOWED_SETTLEMENT_MANAGERS);
  await tx.wait(1);
  console.log('tx:', tx);
}

main();
