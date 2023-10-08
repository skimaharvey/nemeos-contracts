import { ethers } from 'hardhat';

const POOL_FACTORY = '0x6F9B857eDc7De1d2ceA2f3a5e4F2Ad7F2ba40760';
const ALLOWED_NFT_FILTERS = [
  '0x90d5e0cd6E36E274Ed801F1b5a01Af0f2e379D10',
  '0x2aF1fAB0e17dA284bcF11820f8795D82DD74fcc6',
  '0x6B22E1A41a78f47410898f37Ede9afBf17188616',
];

async function main() {
  const poolFactory = await ethers.getContractAt('PoolFactory', POOL_FACTORY);
  const tx = await poolFactory.updateAllowedNFTFilters(ALLOWED_NFT_FILTERS);
  await tx.wait(1);
  console.log('tx:', tx);
}

main();
