import { ethers } from 'hardhat';

const POOL_FACTORY = '0x3740fBf2663A1B9D7e6f1E2b5d75F3b9f47c0664';

// constants to be set by the user
const COLLECTION_ADDRESS = '0xaF614a2ced7eC8CdFfaebC10ba797f6C9ebfcd78';
const POOL_CURRENCY = ethers.constants.AddressZero; // ETH
const POOL_LTV_BPS = 2_000; // 20%
const INITIAL_DAILY_RATES = 20; // 0.1%
const INITIAL_DEPOSIT = ethers.utils.parseEther('0.1'); // 0.1 ETH
const NFT_FILTER = '0x90d5e0cd6E36E274Ed801F1b5a01Af0f2e379D10';
const LIQUIDATOR = '0xc162c3a7393ffAEf4306A3e57A822264dF95B6c1';

async function main() {
  const poolFactory = await ethers.getContractAt('PoolFactory', POOL_FACTORY);

  const poolAddres = await poolFactory.callStatic.createPool(
    COLLECTION_ADDRESS,
    POOL_CURRENCY,
    POOL_LTV_BPS,
    INITIAL_DAILY_RATES,
    INITIAL_DEPOSIT,
    NFT_FILTER,
    LIQUIDATOR,
    { value: INITIAL_DEPOSIT },
  );

  const tx = await poolFactory.createPool(
    COLLECTION_ADDRESS,
    POOL_CURRENCY,
    POOL_LTV_BPS,
    INITIAL_DAILY_RATES,
    INITIAL_DEPOSIT,
    NFT_FILTER,
    LIQUIDATOR,
    { value: INITIAL_DEPOSIT },
  );
  await tx.wait(1);
  console.log('tx:', tx);
  console.log('poolAddres:', poolAddres);
}

// deployed to: 0x87c91Da4A71Ab7E2593aAacc4Fdc0C2379ecc160 with 20% LTV

main();
