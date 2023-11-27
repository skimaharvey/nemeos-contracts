import { ethers } from 'hardhat';

const POOL_FACTORY = '0xfa4B90DcE50d32745661b7baad44a209b33200cE';
const NEW_OWNER = '0x76778AeDe1Afc5031FAb1C761C41130F31415424';

async function main() {
  const poolFactory = await ethers.getContractAt('PoolFactory', POOL_FACTORY);
  const tx = await poolFactory.transferOwnership(NEW_OWNER);
  console.log('tx:', tx);
}

main();
