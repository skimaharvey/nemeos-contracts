import { ethers } from 'hardhat';

const POOL_FACTORY = '0x6F9B857eDc7De1d2ceA2f3a5e4F2Ad7F2ba40760';

async function main() {
  const CollateralFactoryFactory = await ethers.getContractFactory('CollateralFactory');
  const collateralFactory = await CollateralFactoryFactory.deploy(POOL_FACTORY);
  await collateralFactory.deployed();

  console.log('CollateralFactory deployed to:', collateralFactory.address);
  //latest: 0xdABe378CBF191D9E40d4E1a7969200f5B953B04E

  // presentation: 0x846f06F2a153a36bACe39ed087ec834C3c4f903f
}

main();
