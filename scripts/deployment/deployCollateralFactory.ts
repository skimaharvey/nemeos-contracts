import { ethers } from 'hardhat';

const POOL_FACTORY = '0x3740fBf2663A1B9D7e6f1E2b5d75F3b9f47c0664';

async function main() {
  const CollateralFactoryFactory = await ethers.getContractFactory('CollateralFactory');
  const collateralFactory = await CollateralFactoryFactory.deploy(POOL_FACTORY);
  await collateralFactory.deployed();

  console.log('CollateralFactory deployed to:', collateralFactory.address);
}

main();
