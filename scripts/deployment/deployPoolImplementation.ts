import { ethers } from 'hardhat';

async function main() {
  const PoolImplementationFactory = await ethers.getContractFactory('Pool');
  const poolImplementation = await PoolImplementationFactory.deploy();

  console.log('PoolImplementation deployed to:', poolImplementation.address);
}

main();
