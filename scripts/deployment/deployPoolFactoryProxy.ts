import { ethers } from 'hardhat';

const FACTORY_IMPLEMENTATION = '0x6935fb1669C7ddbd7a1E2bF4883146fD6615558b';

async function main() {
  const [deployer] = await ethers.getSigners();

  const ProxyFactory = await ethers.getContractFactory('ERC1967Proxy');
  const proxyFactory = await ProxyFactory.deploy(FACTORY_IMPLEMENTATION, '0x');
  await proxyFactory.deployed();

  console.log('ProxyFactory deployed to:', proxyFactory.address);

  const PoolFactory = await ethers.getContractFactory('PoolFactory');

  // attach the proxy to the PoolFactory interface
  const poolFactory = PoolFactory.attach(proxyFactory.address);

  // initialize the proxy
  await poolFactory.initialize(deployer.address, deployer.address);

  // latest: 0x9c4D44f3c7a157f8b5b6dA4A4E27ff80b015a86a
}

main();
