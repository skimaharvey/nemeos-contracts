import { ethers } from 'hardhat';

const POOL_FACTORY = '0xfa4B90DcE50d32745661b7baad44a209b33200cE';
const NFTWRAPPER_FACTORY = '0x6F2C029a39b8d5eEDE4799adc6f45DB662a3DA84';

async function main() {
  const poolFactory = await ethers.getContractAt('PoolFactory', POOL_FACTORY);
  const tx = await poolFactory.updateNFTWrapperFactory(NFTWRAPPER_FACTORY);
  await tx.wait(1);
  console.log('tx:', tx);
}

main();
