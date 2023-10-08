import { ethers } from 'hardhat';

const POOL_FACTORY = '0x6F9B857eDc7De1d2ceA2f3a5e4F2Ad7F2ba40760';

// constants to be set by the user
const COLLECTION_ADDRESS = '0xdaa3812b8fd34d01711105a6dfb669c50ab8fee3';
const POOL_CURRENCY = ethers.constants.AddressZero; // ETH
const POOL_LTV_BPS = 2_000; // 20%
const INITIAL_DAILY_RATES = 5; // 0.05%
const INITIAL_DEPOSIT = ethers.utils.parseEther('0.1'); // 0.1 ETH
const NFT_FILTER = '0x6B22E1A41a78f47410898f37Ede9afBf17188616';
const LIQUIDATOR = '0x3717e41333C490B9D38779a4155af7D83960951a';

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
