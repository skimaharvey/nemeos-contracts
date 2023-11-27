import { ethers } from 'hardhat';

const POOL_FACTORY = '0xfa4B90DcE50d32745661b7baad44a209b33200cEn';

async function main() {
  const DucthAuctionFactory = await ethers.getContractFactory('DutchAuctionLiquidator');
  const dutchAuctionFactory = await DucthAuctionFactory.deploy(POOL_FACTORY, 7);
  await dutchAuctionFactory.deployed();

  console.log('DutchAuctionFactory deployed to:', dutchAuctionFactory.address);

  // latest: 0x3717e41333C490B9D38779a4155af7D83960951a
}

main();
