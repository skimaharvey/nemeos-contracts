import { ethers } from 'hardhat';

const POOL_FACTORY = '0x3740fBf2663A1B9D7e6f1E2b5d75F3b9f47c0664';
const POOL_IMPLEMENTATION = '0x30A82525fF36D3954E37E06e11d31626896496f6';

async function main() {
  const poolFactory = await ethers.getContractAt('PoolFactory', POOL_FACTORY);
  const tx = await poolFactory.updatePoolImplementation(POOL_IMPLEMENTATION);
  await tx.wait(1);
  console.log('tx:', tx);
}

main();
