import { ethers } from 'hardhat';

const POOL_FACTORY = '0x3740fBf2663A1B9D7e6f1E2b5d75F3b9f47c0664';

async function main() {
  const poolFactory = await ethers.getContractAt('PoolFactory', POOL_FACTORY);

  const pools = await poolFactory.getPools();
  console.log('pools:', pools);
}

// deployed to: 0x87c91Da4A71Ab7E2593aAacc4Fdc0C2379ecc160 with 20% minimal deposit

main();
