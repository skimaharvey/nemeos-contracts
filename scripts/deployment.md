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
   npx hardhat run scripts/deployPoolFactoryImplementation.ts --network goerli
   ```

2. **Deploy PoolFactory Proxy Contract**

   ```bash
   npx hardhat run scripts/deployPoolFactoryProxy.ts --network goerli
   ```

3. **Deploy Seaport Settlement Manager Contract**

   ```bash
   npx hardhat run scripts/deploySeaportSettlementManager.ts --network goerli
   ```

4. **Deploy NFT Filter Contract**

   ```bash
   npx hardhat run scripts/deployNFTFilter.ts --network goerli
   ```

5. **Deploy Dutch Auction Contract**

   ```bash
   npx hardhat run scripts/deployDutchAuctionLiquidator.ts --network goerli
   ```
