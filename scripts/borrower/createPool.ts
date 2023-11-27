import { ethers } from 'hardhat';

const POOL_FACTORY = '0xfa4B90DcE50d32745661b7baad44a209b33200cE';

// constants to be set by the user
const COLLECTION_ADDRESS = '0xbdcf4b6693e344115b951c4796e8622a66cdb728';
const POOL_CURRENCY = ethers.constants.AddressZero; // ETH
const POOL_LTV_BPS = 2_000; // 20%
const INITIAL_DAILY_RATES = 5; // 0.05%
const INITIAL_DEPOSIT = ethers.utils.parseEther('0.1'); // 0.1 ETH
const NFT_FILTER = '0xCaaCaf88244cDb7835568DE966CeBA6657fe02AC';
const LIQUIDATOR = '0xa9b6D3134A629E3181586e22E2737200fa1c734e';

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
