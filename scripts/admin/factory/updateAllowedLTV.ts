import { ethers } from 'hardhat';

const POOL_FACTORY = '0xfa4B90DcE50d32745661b7baad44a209b33200cE';
const ALLOWED_LTVs_BPS = [1_000, 2_000]; //  10_000 == 100%

async function main() {
  const poolFactory = await ethers.getContractAt('PoolFactory', POOL_FACTORY);
  const tx = await poolFactory.updateAllowedLTVs(ALLOWED_LTVs_BPS);
  await tx.wait(1);
  console.log('tx:', tx);
}

main();
