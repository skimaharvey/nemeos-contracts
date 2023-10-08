import { ethers } from 'hardhat';

const POOL_FACTORY = '0x6F9B857eDc7De1d2ceA2f3a5e4F2Ad7F2ba40760';
const ALLOWED_LTVs_BPS = [1_000, 2_000]; //  10_000 == 100%

async function main() {
  const poolFactory = await ethers.getContractAt('PoolFactory', POOL_FACTORY);
  const tx = await poolFactory.updateAllowedLTVs(ALLOWED_LTVs_BPS);
  await tx.wait(1);
  console.log('tx:', tx);
}

main();
