import { ethers } from 'hardhat';

const ADDRESS_ORACLE = '0x1BBcaB52070b25CF716C32e53791146A7525cddE';
const SETTLEMENT_MANAGERS = [
  '0xF7eea5164fA57a0dbC2eFBdf18e09062bebCCa4b',
  '0x8578808D6C5d2BE3396dfA647B661D56119F7cec',
];

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

  // latest: 0x90d5e0cd6E36E274Ed801F1b5a01Af0f2e379D10
}

main();
