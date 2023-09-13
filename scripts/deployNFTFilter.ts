import { ethers } from 'hardhat';

const FACTORY_IMPLEMENTATION = '';
const ADDRESS_ORACLE = '';
const SETTLEMENT_MANAGERS = [''];

async function main() {
  const [deployer] = await ethers.getSigners();

  const NFTFilterFactory = await ethers.getContractFactory('NFTFilter');
  const nftFilterFactory = await NFTFilterFactory.deploy(
    ADDRESS_ORACLE,
    deployer.address,
    SETTLEMENT_MANAGERS,
  );
  await nftFilterFactory.deployed();

  console.log('NFTFilterFactory deployed to:', nftFilterFactory.address);
}

main();
