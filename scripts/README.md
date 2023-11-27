# Smart Contract Deployment Guide

This document outlines the steps required to deploy various smart contracts using Hardhat. Make sure to follow the instructions carefully to ensure a successful deployment.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Environment Setup](#environment-setup)
- [Deployment Steps](#deployment-steps)

---

## Prerequisites

Before you proceed, ensure you have the following:

- Node.js and npm installed
- Hardhat installed globally or as a project dependency

---

## Environment Setup

1. **Environment Variables**: Create a `.env` file in the project's root directory and populate it with the necessary variables.

   ```bash
   INFURA_API_KEY=<Your Infura API Key>
   PVT_KEY=<Your Private Key>
   ```

2. **Install Dependencies**: Run the following command to install the required npm packages.

   ```bash
   npm install
   ```

---

## Deployment Steps

Follow these steps to deploy your smart contracts:

1. **Deploy PoolFactory Implementation Contract**

```bash
  npx hardhat run scripts/deployment/deployPoolFactoryImplementation.ts --network goerli
```

Currently deployed at `0x5Ba6Ee4766Cfd3247ed811f1171306D98fEf6d89`

2. **Deploy PoolFactory Proxy Contract**

Add the PoolFactory Implementation Contract address to the `POOL_FACTORY_IMPLEMENTATION` variable in the `deployPoolFactoryProxy.ts` script and then run the following command:

```bash
npx hardhat run scripts/deployment/deployPoolFactoryProxy.ts --network goerli
```

Currently deployed at `0xfa4B90DcE50d32745661b7baad44a209b33200cE`

3. **Deploy Collateral Factory Contract**

Update the `POOL_FACTORY` variable in the `deployCollateralFactory.ts` script with the Pool Factory Proxy address and then run the following command:

```bash
   npx hardhat run scripts/deployment/deployCollateralFactory.ts --network goerli
```

Currently deployed at `0x6F2C029a39b8d5eEDE4799adc6f45DB662a3DA84`

4. **Deploy Seaport Settlement Manager Contract**

Run the following command:

```bash
   npx hardhat run scripts/deployment/deploySeaportManager.ts --network goerli
```

Currently deployed at `0xDA5A3aFD2948b11026DA2f5fa76588aC0893a610`

5. **Deploy NFT Filter Contract**

Add the Oracle address to the `ORACLE_ADDRESS` variable and the Settlement Managers supported in the `SETTLEMENT_MANAGERS` variable in the `deployNFTFilter.ts` script and then run the following command:

```bash
npx hardhat run scripts/deployment/deployNFTFilter.ts --network goerli
```

Currently deployed at `0xCaaCaf88244cDb7835568DE966CeBA6657fe02AC`

6. **Deploy Dutch Auction Contract**

Add the PoolFactory Proxy Contract address to the `POOL_FACTORY` variable in the `deployDutchAuction.ts` script and then run the following command:

```bash
npx hardhat run scripts/deployment/deployDutchAuctionLiquidator.ts --network goerli
```

Currently deployed at `0xa9b6D3134A629E3181586e22E2737200fa1c734e`

7. **Deploy Pool Implementation Contract**

```bash
npx hardhat run scripts/deployment/deployPoolImplementation.ts --network goerli
```

Currently deployed at `0xcB8f844Ef36C0c89291fd59920Fc40aa80BBAd0B`

## Update Pool Factory Proxy Contract

In order to be able to deploy new pools, you will first need to update the following variables.

1. **Update the Allowed LTVs**

Add the Pool Factory Proxy Contract address to the `POOL_FACTORY` variable in the `updateAllowedLTVs.ts` script and then run the following command:

```bash
npx hardhat run scripts/admin/factory/updateAllowedLTV.ts --network goerli
```

2. **Update the Allowed NFT Filters**

- Add the Pool Factory Proxy Contract address to the `POOL_FACTORY` variable in the `updateAllowedNFTFilters.ts` script.
- Add the NFT Filter Contract address to the `NFT_FILTER` variable in the `updateAllowedNFTFilters.ts` script.
- Run the following command:

```bash
npx hardhat run scripts/admin/factory/updateAllowedNFTFilter.ts --network goerli
```

3. **Update the CollateralFactory**

- Add the Pool Factory Proxy Contract address to the `POOL_FACTORY` variable in the `updateCollateralFactory.ts` script.
- Add the Collateral Factory Contract address to the `COLLATERAL_FACTORY` variable in the `updateCollateralFactory.ts` script.
- Run the following command:

```bash
npx hardhat run scripts/admin/factory/updateCollateralFactory.ts --network goerli
```

4. **Update the Pool Implementation Address**

- Add the Pool Factory Proxy Contract address to the `POOL_FACTORY` variable in the `updatePoolImplementation.ts` script.
- Add the Pool Implementation Contract address to the `POOL_IMPLEMENTATION` variable in the `updatePoolImplementation.ts` script.
- Run the following command:

```bash
npx hardhat run scripts/admin/factory/updatePoolImplementation.ts --network goerli
```

5. **Update AllowedLiquidators**

- Add the Pool Factory Proxy Contract address to the `POOL_FACTORY` variable in the `updateAllowedLiquidators.ts` script.
- Add the Dutch Auction Contract address to the `DUTCH_AUCTION` variable in the `updateAllowedLiquidators.ts` script.
- Run the following command:

```bash
npx hardhat run scripts/admin/factory/updateAllowedLiquidators.ts --network goerli
```
