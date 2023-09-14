import { ethers } from 'hardhat';

const ADDRESS_ORACLE = '0x1BBcaB52070b25CF716C32e53791146A7525cddE';
const SETTLEMENT_MANAGERS = ['0xF7eea5164fA57a0dbC2eFBdf18e09062bebCCa4b'];

async function main() {
  const [deployer] = await ethers.getSigners();

  const NFTFilterFactory = await ethers.getContractFactory('NFTFilter');
  const nftFilterFactory = await NFTFilterFactory.deploy(
    ADDRESS_ORACLE,
    deployer.address,
    SETTLEMENT_MANAGERS,
  );
  await nftFilterFactory.deployed();

  console.log('NFTFilterFactory deployed to:', nftFilterFactory.address);
}

main();
