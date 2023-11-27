import { ethers } from 'hardhat';

const ADDRESS_ORACLE = '0x44e86DAa852673315e757F1C866fa125973a43f4';
const SETTLEMENT_MANAGERS = ['0xDA5A3aFD2948b11026DA2f5fa76588aC0893a610'];

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
