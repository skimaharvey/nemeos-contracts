import { ethers } from 'hardhat';

const POOL_FACTORY = '0x3740fBf2663A1B9D7e6f1E2b5d75F3b9f47c0664';
const ALLOWED_NFT_FILTERS = ['0x90d5e0cd6E36E274Ed801F1b5a01Af0f2e379D10']; //  10_000 == 100%

async function main() {
  const poolFactory = await ethers.getContractAt('PoolFactory', POOL_FACTORY);
  const tx = await poolFactory.updateAllowedNFTFilters(ALLOWED_NFT_FILTERS);
  await tx.wait(1);
  console.log('tx:', tx);
}

main();
