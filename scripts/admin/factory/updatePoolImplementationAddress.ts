import { ethers } from 'hardhat';

const POOL_FACTORY = '0x6F9B857eDc7De1d2ceA2f3a5e4F2Ad7F2ba40760';
const POOL_IMPLEMENTATION = '0xBD5184EcB49d98f3d306E50Fa68Ca6fc32EE843e';

async function main() {
  const poolFactory = await ethers.getContractAt('PoolFactory', POOL_FACTORY);
  const tx = await poolFactory.updatePoolImplementation(POOL_IMPLEMENTATION);
  await tx.wait(1);
  console.log('tx:', tx);
}

main();
