import { ethers } from 'hardhat';

const POOL_FACTORY = '0xfa4B90DcE50d32745661b7baad44a209b33200cE';
const ALLOWED_NFT_FILTERS = [
  '0x90d5e0cd6E36E274Ed801F1b5a01Af0f2e379D10',
  '0x2aF1fAB0e17dA284bcF11820f8795D82DD74fcc6',
  '0x6B22E1A41a78f47410898f37Ede9afBf17188616',
  '0xCaaCaf88244cDb7835568DE966CeBA6657fe02AC',
];

async function main() {
  const poolFactory = await ethers.getContractAt('PoolFactory', POOL_FACTORY);
  const tx = await poolFactory.updateAllowedNFTFilters(ALLOWED_NFT_FILTERS);
  await tx.wait(1);
  console.log('tx:', tx);
}

main();
