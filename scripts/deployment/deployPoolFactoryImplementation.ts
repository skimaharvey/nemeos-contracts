import { ethers } from 'hardhat';

async function main() {
  const PoolFactoryFactory = await ethers.getContractFactory('PoolFactory');
  const PoolFactory = await PoolFactoryFactory.deploy();
  await PoolFactory.deployed();

  console.log('PoolFactory deployed to:', PoolFactory.address);
}

main();
