import { ethers } from 'hardhat';

const POOL_FACTORY = '0x9c4D44f3c7a157f8b5b6dA4A4E27ff80b015a86a';

async function main() {
  const CollateralFactoryFactory = await ethers.getContractFactory('CollateralFactory');
  const collateralFactory = await CollateralFactoryFactory.deploy(POOL_FACTORY);
  await collateralFactory.deployed();

  console.log('CollateralFactory deployed to:', collateralFactory.address);
  //latest: 0xdABe378CBF191D9E40d4E1a7969200f5B953B04E
}

main();
