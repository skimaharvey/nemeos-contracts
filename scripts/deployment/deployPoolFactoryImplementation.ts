import { ethers } from 'hardhat';

async function main() {
  const gasPrice = await ethers.provider.getGasPrice();
  const PoolFactoryFactory = await ethers.getContractFactory('PoolFactory');
  const PoolFactory = await PoolFactoryFactory.deploy({
    gasPrice: gasPrice.add(ethers.utils.parseUnits('30', 'gwei')),
  });
  await PoolFactory.deployed();

  console.log('PoolFactory deployed to:', PoolFactory.address);

  // latest: 0x6935fb1669C7ddbd7a1E2bF4883146fD6615558b

  // presentation: 0x63A3e5b5C738f8943Df4Dd498133f8Cedee2b18A
}

main();
