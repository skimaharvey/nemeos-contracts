import { ethers } from 'hardhat';

const POOL_ADDRESS = '0x1ac456E76d32945185deb3334Fa86f49FD441A8d';
const DAILY_INTEREST_BPS = 10;

async function main() {
  const [signer] = await ethers.getSigners();

  const pool = await ethers.getContractAt('Pool', POOL_ADDRESS);

  const tx = await pool.depositAndVote(signer.address, DAILY_INTEREST_BPS, {
    value: ethers.utils.parseEther('0.1'),
  });

  console.log('gas', tx.hash);
}

main();
