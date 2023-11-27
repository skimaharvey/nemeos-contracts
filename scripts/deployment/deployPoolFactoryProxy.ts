import { ethers } from 'hardhat';

const FACTORY_IMPLEMENTATION = '0x5Ba6Ee4766Cfd3247ed811f1171306D98fEf6d89';

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
  await poolFactory.initialize(deployer.address, deployer.address, 1, 1000);

  // latest: 0x9c4D44f3c7a157f8b5b6dA4A4E27ff80b015a86a

  // presentation: 0x6F9B857eDc7De1d2ceA2f3a5e4F2Ad7F2ba40760
}

main();
