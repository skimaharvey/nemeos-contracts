import { ethers } from 'hardhat';

async function main() {
  const PoolImplementationFactory = await ethers.getContractFactory('Pool');
  const poolImplementation = await PoolImplementationFactory.deploy();

  console.log('PoolImplementation deployed to:', poolImplementation.address);

  //latest: 0x34FC83C00E9c2886379AE408Ed3dAfEA3A091544
}

main();
