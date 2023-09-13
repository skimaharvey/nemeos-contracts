import { ethers } from 'hardhat';

const FACTORY_IMPLEMENTATION = '0x955B171c1b3aCdd4C01e1b55e765C4f37b3230eD';

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
