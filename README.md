# Nemeos Smart Contracts

## Introduction

This protocol includes several contracts:

- [Pool Factory](./contracts/Lending/PoolFactory.sol): Manages the creation of Pools.
- [Pool](./contracts/Lending/Pool.sol): A 4626 Native Token Vault handling liquidity.
- [NFTFilter](./contracts/Lending/NFTFilter.sol): Ensures transactions are signed by an offchain oracle.
- [NFTWrapper Factory](./contracts/Lending/NFTWrapperFactory.sol): Mints NFT wrappers post-loan.
- [NFTWrapper](./contracts/Lending/NFTWrapper.sol): The wrapper itself.
- [SeaportSettlementManager](./contracts/Lending/SeaportSettlementManager.sol).
- [DutchAuctionLiquidation](./contracts/Lending/DutchAuctionLiquidation.sol): Liquidates NFTs in the event of a paiment default or if the borrower wishes to liquidate their loan.

The process allows anyone to create a Pool for a specific collection at a designated `minimalDepositRequested`.
Liquidity providers deposit funds, receiving shares in return, and vote on lending rates. Borrowers can use this liquidity to purchase an NFT from the specified collection (acquired via Seaport through the `SeaportSettlementManager`). They must repay their loan within a set interval (30 days). Upon purchase, a Wrapper NFT is minted, which is burnt upon full repayment, and the actual NFT is transferred to the borrower.

If borrower fails to repay, the Wrapper will be burnt and the NFT will be send to Dutch Auction Liquidation.

## Design Decisions

- We are aware that the protocol is not fully compliant with the ERC-4626 standard as we wanted to use native tokens but still found it useful to implement the standard as we might in the future accept other tokens and could as well still use the logic of shares that comes with vaults.
- The NFT collection we will support will be added to the PoolFactory contract by the team. We will make sure they are compliant with the ERC-721 standard and our protocol. We will not allow NFT that have 'weird' properties that could make it dangerous to lend against them.
- we purposely do not use `safeTransferFrom` in the `Pool` as we dont see any reason to use it.
- `Oracle` in the `NFTFilter` is an offchain agent ran by Nemeos in charge of verifying the validity of the loan (including params like the `settlementManager`, coherent floor price, etc.).
