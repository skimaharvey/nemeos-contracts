import { ethers } from 'hardhat';

const POOL_FACTORY = '0x9c4D44f3c7a157f8b5b6dA4A4E27ff80b015a86a';
const POOL_IMPLEMENTATION = '0x34FC83C00E9c2886379AE408Ed3dAfEA3A091544';

async function main() {
  const poolFactory = await ethers.getContractAt('PoolFactory', POOL_FACTORY);
  const tx = await poolFactory.updatePoolImplementation(POOL_IMPLEMENTATION);
  await tx.wait(1);
  console.log('tx:', tx);
}

main();
