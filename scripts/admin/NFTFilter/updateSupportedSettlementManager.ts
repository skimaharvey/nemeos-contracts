import { ethers } from 'hardhat';

const NFT_FILTER_ADDRESS = '0xCaaCaf88244cDb7835568DE966CeBA6657fe02AC';
const ALLOWED_SETTLEMENT_MANAGERS = [
  '0xC385568955b1434207bbC598026Da0d145aC7436',
  '0x9B213ca33427697D7D5FD3e3d7b6377b673168DD',
  '0x8578808D6C5d2BE3396dfA647B661D56119F7cec', // latest seaport settler
];

async function main() {
  const nftFilter = await ethers.getContractAt('NFTFilter', NFT_FILTER_ADDRESS);

  console.log(
    'supportedSettlementManagers[0]',
    await nftFilter.supportedSettlementManagers(0).catch(() => {}),
  );
  console.log(
    'supportedSettlementManagers[1]',
    await nftFilter.supportedSettlementManagers(1).catch(() => {}),
  );
  console.log(
    'supportedSettlementManagers[2]',
    await nftFilter.supportedSettlementManagers(2).catch(() => {}),
  );
  // console.log('supportedSettlementManagers[3]', await nftFilter.supportedSettlementManagers(3));

  console.log('protocolAdmin', await nftFilter.protocolAdmin());

  const tx = await nftFilter.updatesupportedSettlementManagers(ALLOWED_SETTLEMENT_MANAGERS);
  await tx.wait(1);
  console.log('tx:', tx);
}

main();
