import { ethers } from 'hardhat';

const POOL_FACTORY = '0x3740fBf2663A1B9D7e6f1E2b5d75F3b9f47c0664';

async function main() {
  const DucthAuctionFactory = await ethers.getContractFactory('DutchAuctionCollateralLiquidator');
  const dutchAuctionFactory = await DucthAuctionFactory.deploy(POOL_FACTORY, 7);
  await dutchAuctionFactory.deployed();

  console.log('DutchAuctionFactory deployed to:', dutchAuctionFactory.address);
}

main();
