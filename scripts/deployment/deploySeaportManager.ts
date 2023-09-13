import { ethers } from 'hardhat';

async function main() {
  const SeaportManagerFactory = await ethers.getContractFactory('SeaportSettlementManager');
  const seaportManager = await SeaportManagerFactory.deploy();
  await seaportManager.deployed();

  console.log('seaportManager deployed to:', seaportManager.address);
}

main();
