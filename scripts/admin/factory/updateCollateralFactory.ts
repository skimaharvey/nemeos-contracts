import { ethers } from 'hardhat';

const POOL_FACTORY = '0x9c4D44f3c7a157f8b5b6dA4A4E27ff80b015a86a';
const COLLATERAL_FACTORY = '0xdABe378CBF191D9E40d4E1a7969200f5B953B04E';

async function main() {
  const poolFactory = await ethers.getContractAt('PoolFactory', POOL_FACTORY);
  const tx = await poolFactory.updateCollateralFactory(COLLATERAL_FACTORY);
  await tx.wait(1);
  console.log('tx:', tx);
}

main();
