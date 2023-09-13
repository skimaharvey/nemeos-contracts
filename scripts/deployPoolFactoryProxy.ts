import { ethers } from 'hardhat';

const FACTORY_IMPLEMENTATION = '';

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
}

main();
