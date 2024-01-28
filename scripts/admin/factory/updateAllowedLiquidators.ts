import { ethers } from 'hardhat';

const POOL_FACTORY = '0xfa4B90DcE50d32745661b7baad44a209b33200cE';
const ALLOWED_MinimaDeposits_IN_BPS = ['0xa9b6D3134A629E3181586e22E2737200fa1c734e']; //  10_000 == 100%

async function main() {
  const poolFactory = await ethers.getContractAt('PoolFactory', POOL_FACTORY);
  const tx = await poolFactory.updateAllowedLiquidators(ALLOWED_MinimaDeposits_IN_BPS);
  await tx.wait(1);
  console.log('tx:', tx);
}

main();
