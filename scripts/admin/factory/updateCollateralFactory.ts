import { ethers } from 'hardhat';

const POOL_FACTORY = '0x3740fBf2663A1B9D7e6f1E2b5d75F3b9f47c0664';
const COLLATERAL_FACTORY = '0xC385568955b1434207bbC598026Da0d145aC7436';

async function main() {
  const poolFactory = await ethers.getContractAt('PoolFactory', POOL_FACTORY);
  const tx = await poolFactory.updateCollateralFactory(COLLATERAL_FACTORY);
  await tx.wait(1);
  console.log('tx:', tx);
}

main();
