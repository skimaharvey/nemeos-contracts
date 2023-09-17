import { ethers } from 'hardhat';

async function main() {
  const SeaportManagerFactory = await ethers.getContractFactory('SeaportSettlementManager');
  const seaportManager = await SeaportManagerFactory.deploy();
  await seaportManager.deployed();

  console.log('seaportManager deployed to:', seaportManager.address);

  //latest: 0x8578808D6C5d2BE3396dfA647B661D56119F7cec
}

main();
