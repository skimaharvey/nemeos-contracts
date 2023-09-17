import { ethers } from 'hardhat';

async function main() {
  const PoolFactoryFactory = await ethers.getContractFactory('PoolFactory');
  const PoolFactory = await PoolFactoryFactory.deploy();
  await PoolFactory.deployed();

  console.log('PoolFactory deployed to:', PoolFactory.address);

  // latest: 0x6935fb1669C7ddbd7a1E2bF4883146fD6615558b
}

main();
