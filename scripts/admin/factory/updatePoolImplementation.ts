import { ethers } from 'hardhat';

const POOL_FACTORY = '0xfa4B90DcE50d32745661b7baad44a209b33200cE';
const POOL_IMPLEMENTATION = '0xcB8f844Ef36C0c89291fd59920Fc40aa80BBAd0B';

async function main() {
  const poolFactory = await ethers.getContractAt('PoolFactory', POOL_FACTORY);
  const tx = await poolFactory.updatePoolImplementation(POOL_IMPLEMENTATION);
  await tx.wait(1);
  console.log('tx:', tx);
}

main();
