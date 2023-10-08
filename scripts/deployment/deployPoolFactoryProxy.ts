import { ethers } from 'hardhat';

const FACTORY_IMPLEMENTATION = '0x63A3e5b5C738f8943Df4Dd498133f8Cedee2b18A';

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

  // presentation: 0x6F9B857eDc7De1d2ceA2f3a5e4F2Ad7F2ba40760
}

main();
