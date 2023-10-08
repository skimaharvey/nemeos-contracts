import { ethers } from 'hardhat';

const POOL_FACTORY = '0x6F9B857eDc7De1d2ceA2f3a5e4F2Ad7F2ba40760';
const COLLATERAL_FACTORY = '0x846f06F2a153a36bACe39ed087ec834C3c4f903f';

async function main() {
  const poolFactory = await ethers.getContractAt('PoolFactory', POOL_FACTORY);
  const tx = await poolFactory.updateCollateralFactory(COLLATERAL_FACTORY);
  await tx.wait(1);
  console.log('tx:', tx);
}

main();
