import { ethers } from 'hardhat';

const POOL_FACTORY = '0x3740fBf2663A1B9D7e6f1E2b5d75F3b9f47c0664';
const ALLOWED_LTVs_BPS = [2_000]; //  10_000 == 100%

async function main() {
  const poolFactory = await ethers.getContractAt('PoolFactory', POOL_FACTORY);
  const tx = await poolFactory.updateAllowedLtv([ALLOWED_LTVs_BPS]);
  await tx.wait(1);
  console.log('tx:', tx);
}

main();
