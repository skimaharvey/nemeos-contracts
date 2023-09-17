import { ethers } from 'hardhat';

const POOL_FACTORY = '0x9c4D44f3c7a157f8b5b6dA4A4E27ff80b015a86a';
const ALLOWED_LTVs_BPS = [1_000, 2_000]; //  10_000 == 100%

async function main() {
  const poolFactory = await ethers.getContractAt('PoolFactory', POOL_FACTORY);
  const tx = await poolFactory.updateAllowedLTVs(ALLOWED_LTVs_BPS);
  await tx.wait(1);
  console.log('tx:', tx);
}

main();
