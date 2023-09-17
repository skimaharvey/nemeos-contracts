import { ethers } from 'hardhat';

const POOL_FACTORY = '0x9c4D44f3c7a157f8b5b6dA4A4E27ff80b015a86a';

async function main() {
  const DucthAuctionFactory = await ethers.getContractFactory('DutchAuctionCollateralLiquidator');
  const dutchAuctionFactory = await DucthAuctionFactory.deploy(POOL_FACTORY, 7);
  await dutchAuctionFactory.deployed();

  console.log('DutchAuctionFactory deployed to:', dutchAuctionFactory.address);

  // latest: 0x3717e41333C490B9D38779a4155af7D83960951a
}

main();
