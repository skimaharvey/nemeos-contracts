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

Currently deployed at `0x955B171c1b3aCdd4C01e1b55e765C4f37b3230eD`

2. **Deploy PoolFactory Proxy Contract**

Add the PoolFactory Implementation Contract address to the `POOL_FACTORY_IMPLEMENTATION` variable in the `deployPoolFactoryProxy.ts` script and then run the following command:

```bash
npx hardhat run scripts/deployment/deployPoolFactoryProxy.ts --network goerli
```

Currently deployed at `0x3740fBf2663A1B9D7e6f1E2b5d75F3b9f47c0664`

3. **Deploy Seaport Settlement Manager Contract**

```bash
   npx hardhat run scripts/deployment/deploySeaportSettlementManager.ts --network goerli
```

Currently deployed at `0xF7eea5164fA57a0dbC2eFBdf18e09062bebCCa4b`

4. **Deploy NFT Filter Contract**

Add the Oracle address to the `ORACLE_ADDRESS` variable and the Settlement Managers supported in the `SETTLEMENT_MANAGERS` variable in the `deployNFTFilter.ts` script and then run the following command:

```bash
npx hardhat run scripts/deployment/deployNFTFilter.ts --network goerli
```

Currently deployed at `0x90d5e0cd6E36E274Ed801F1b5a01Af0f2e379D10`

5. **Deploy Dutch Auction Contract**

Add the PoolFactory Proxy Contract address to the `POOL_FACTORY` variable in the `deployDutchAuction.ts` script and then run the following command:

```bash
npx hardhat run scripts/deployment/deployDutchAuctionLiquidator.ts --network goerli
```

Currently deployed at `0xc162c3a7393ffAEf4306A3e57A822264dF95B6c1`
