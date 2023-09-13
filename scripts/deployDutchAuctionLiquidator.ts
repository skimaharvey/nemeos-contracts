import { ethers } from 'hardhat';

const POOL_FACTORY = '';

async function main() {
  const DucthAuctionFactory = await ethers.getContractFactory('DutchAuctionCollateralLiquidator');
  const dutchAuctionFactory = await DucthAuctionFactory.deploy(POOL_FACTORY, 7);
  await dutchAuctionFactory.deployed();

  console.log('DutchAuctionFactory deployed to:', dutchAuctionFactory.address);
}

main();
