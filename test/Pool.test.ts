import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { expect } from 'chai';
import '@openzeppelin/hardhat-upgrades';
import OfferData from './fullfil-offer-data.json';
import { buyNFTHelper, buyNFTPreparationHelper, mockSignLoan } from './helpers';
import { Pool } from '../typechain-types';

describe('Pool', async () => {
  let snapshotId: any;

  beforeEach(async function () {
    snapshotId = await ethers.provider.send('evm_snapshot', []);
  });

  afterEach(async function () {
    // reset chain state to before each test
    await ethers.provider.send('evm_revert', [snapshotId]);
  });

  const buildTestContext = async () => {
    const [poolFactoryOwner, protocolFeeCollector, proxyAdmin, oracleSigner, borrower, randomUser] =
      await ethers.getSigners();

    const ethWhale = '0xda9dfa130df4de4673b89022ee50ff26f6ea73cf';
    const impersonatedWhaleSigner = await ethers.getImpersonatedSigner(ethWhale);

    const collectionAddress =
      OfferData.fulfillment_data.transaction.input_data.parameters.offerToken;

    const loanToValueInBps = 3_000; // 30%
    const initialDailyInterestRateInBps = 50;
    const initialDeposit = ethers.utils.parseEther('1');

    // Deploy the implementation contract
    const PoolFactory = await ethers.getContractFactory('PoolFactory');
    const poolFactoryImpl = await PoolFactory.deploy();
    await poolFactoryImpl.deployed();

    // Deploy the TransparentUpgradeableProxy contract
    const TransparentUpgradeableProxy = await ethers.getContractFactory(
      'TransparentUpgradeableProxy',
    );
    const proxy = await TransparentUpgradeableProxy.deploy(
      poolFactoryImpl.address, // logic
      proxyAdmin.address, // admin
      [], // data
    );
    await proxy.deployed();
    const poolFactoryProxy = PoolFactory.attach(proxy.address);
    await poolFactoryProxy.initialize(poolFactoryOwner.address, protocolFeeCollector.address);

    // deploy liquidator
    const randomLiquidatorAddress = ethers.utils.hexlify(ethers.utils.randomBytes(20));
    const DutchAuctionLiquidatoFactory = await ethers.getContractFactory(
      'DutchAuctionCollateralLiquidator',
    );
    const dutchAuctionLiquidatorFactory = await DutchAuctionLiquidatoFactory.deploy(
      poolFactoryProxy.address,
      7,
    );
    await dutchAuctionLiquidatorFactory.deployed();

    // deploy Collateral Factory
    const CollateralFactory = await ethers.getContractFactory('CollateralFactory');
    const collateralFactory = await CollateralFactory.deploy(poolFactoryProxy.address);
    await collateralFactory.deployed();

    // deploy Pool implementation
    const Pool = await ethers.getContractFactory('Pool');
    const poolImpl = await Pool.deploy();
    await poolImpl.deployed();

    // deploy Seaport Settlement Manager contract
    const SeaportSettlementManager = await ethers.getContractFactory('SeaportSettlementManager');
    const seaportSettlementManager = await SeaportSettlementManager.deploy();
    await seaportSettlementManager.deployed();

    // deploy NFT Filter contract
    const NFTFilter = await ethers.getContractFactory('NFTFilter');
    const nftFilter = await NFTFilter.deploy(oracleSigner.address, protocolFeeCollector.address, [
      seaportSettlementManager.address,
    ]);
    await nftFilter.deployed();
    const nftFilterAddress = nftFilter.address;

    // create token contract with collectionAddress
    const tokenContract = await ethers.getContractAt('ERC721', collectionAddress);

    // todo: add pool to Collateral wrapper

    // update collateral factory to poolFactory
    await poolFactoryProxy.updateCollateralFactory(collateralFactory.address);

    // update pool implementation to poolFactory
    await poolFactoryProxy.updatePoolImplementation(poolImpl.address);

    // update allowed ltv to poolFactory
    await poolFactoryProxy.updateAllowedLtv([loanToValueInBps]);

    // update allowed NFT filters to poolFactory
    await poolFactoryProxy.updateAllowedNFTFilters([nftFilterAddress]);

    // deploy Pool proxy through poolFactory
    const poolProxyAddress = await poolFactoryProxy.callStatic.createPool(
      collectionAddress,
      ethers.constants.AddressZero,
      loanToValueInBps,
      initialDailyInterestRateInBps,
      initialDeposit,
      nftFilterAddress,
      randomLiquidatorAddress,
      { value: initialDeposit },
    );

    await poolFactoryProxy.createPool(
      collectionAddress,
      ethers.constants.AddressZero,
      loanToValueInBps,
      initialDailyInterestRateInBps,
      initialDeposit,
      nftFilterAddress,
      dutchAuctionLiquidatorFactory.address,
      { value: initialDeposit },
    );

    const poolProxy: Pool = Pool.attach(poolProxyAddress);

    return {
      poolFactoryImpl,
      poolFactoryProxy,
      poolFactoryOwner,
      loanToValueInBps,
      collectionAddress,
      initialDailyInterestRateInBps,
      randomLiquidatorAddress,
      nftFilterAddress,
      collateralFactory,
      poolProxy,
      impersonatedWhaleSigner,
      randomUser,
      seaportSettlementManager,
      oracleSigner,
      borrower,
      dutchAuctionLiquidatorFactory,
      tokenContract,
    };
  };

  describe('Buy NFT', async () => {
    it('should be able to buy NFT from Seaport', async () => {
      const {
        poolProxy,
        impersonatedWhaleSigner,
        initialDailyInterestRateInBps,
        seaportSettlementManager,
        loanToValueInBps,
        collectionAddress,
        oracleSigner,
        borrower,
      } = await buildTestContext();

      const { tokenId, orderExtraData, loanTimestamp, nftPrice } = await buyNFTPreparationHelper();

      const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

      // deposit into pool
      const deposit = ethers.utils.parseEther('100');
      await poolProxy
        .connect(impersonatedWhaleSigner)
        .depositNativeTokens(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
          value: deposit,
        });

      const loanDurationInDays = 30;
      const loanDurationInSeconds = loanDurationInDays * 24 * 60 * 60;

      // remaining to be paid
      const remainingToBePaid = nftPrice - ltvValue;

      const remainingToBePaidInBN = BigNumber.from(remainingToBePaid.toString());

      // calculate LoanPrice from NFT price
      const [loanPrice] = await poolProxy.calculateLoanPrice(
        remainingToBePaidInBN,
        loanDurationInDays,
      );

      const priceWithInterest = loanPrice.add(BigNumber.from(ltvValue.toString()));

      const oracleSignature = await mockSignLoan(
        collectionAddress,
        tokenId,
        BigNumber.from(nftPrice.toString()),
        priceWithInterest,
        borrower.address,
        0,
        loanTimestamp,
        orderExtraData,
        oracleSigner,
      );

      // buy NFT
      await buyNFTHelper(
        poolProxy,
        borrower,
        collectionAddress,
        tokenId,
        BigNumber.from(nftPrice.toString()),
        priceWithInterest,
        seaportSettlementManager,
        loanTimestamp,
        loanDurationInSeconds,
        orderExtraData,
        oracleSignature,
        BigNumber.from(ltvValue.toString()),
      );
    });
  });

  describe('Deposit', async () => {
    it('should be able to deposit into pool', async () => {
      const { initialDailyInterestRateInBps, poolProxy, impersonatedWhaleSigner } =
        await buildTestContext();

      const poolProxyBalanceBefore = await ethers.provider.getBalance(poolProxy.address);

      const secondDeposit = ethers.utils.parseEther('100');
      await poolProxy
        .connect(impersonatedWhaleSigner)
        .depositNativeTokens(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
          value: secondDeposit,
        });

      const poolProxyBalanceAfter = await ethers.provider.getBalance(poolProxy.address);

      expect(poolProxyBalanceAfter).to.equal(poolProxyBalanceBefore.add(secondDeposit));
    });
  });

  describe('liquidation', async () => {
    it('should revert when trying to liquidate a non-existent loan', async () => {
      const { poolProxy, borrower } = await buildTestContext();

      // Try to liquidate a loan with a non-existent tokenId or borrower
      await expect(
        poolProxy.connect(borrower).liquidateLoan(9999, borrower.address),
      ).to.be.revertedWith('Pool: loan does not exist');
    });

    it('should revert when trying to liquidate a loan already in liquidation', async () => {
      const {
        poolProxy,
        impersonatedWhaleSigner,
        initialDailyInterestRateInBps,
        seaportSettlementManager,
        loanToValueInBps,
        collectionAddress,
        oracleSigner,
        borrower,
        tokenContract,
        dutchAuctionLiquidatorFactory,
        randomUser,
      } = await buildTestContext();

      const { tokenId, orderExtraData, loanTimestamp, nftPrice } = await buyNFTPreparationHelper();

      const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

      // deposit into pool
      const deposit = ethers.utils.parseEther('100');
      await poolProxy
        .connect(impersonatedWhaleSigner)
        .depositNativeTokens(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
          value: deposit,
        });

      const loanDurationInDays = 90;
      const loanDurationInSeconds = loanDurationInDays * 24 * 60 * 60;

      // remaining to be paid
      const remainingToBePaid = nftPrice - ltvValue;

      const remainingToBePaidInBN = BigNumber.from(remainingToBePaid.toString());

      // calculate LoanPrice from NFT price
      const [loanPrice] = await poolProxy.calculateLoanPrice(
        remainingToBePaidInBN,
        loanDurationInDays,
      );

      const priceWithInterest = loanPrice.add(BigNumber.from(ltvValue.toString()));

      const oracleSignature = await mockSignLoan(
        collectionAddress,
        tokenId,
        BigNumber.from(nftPrice.toString()),
        priceWithInterest,
        borrower.address,
        0,
        loanTimestamp,
        orderExtraData,
        oracleSigner,
      );

      // buy NFT
      await buyNFTHelper(
        poolProxy,
        borrower,
        collectionAddress,
        tokenId,
        BigNumber.from(nftPrice.toString()),
        priceWithInterest,
        seaportSettlementManager,
        loanTimestamp,
        loanDurationInSeconds,
        orderExtraData,
        oracleSignature,
        BigNumber.from(ltvValue.toString()),
      );

      const thirthyDaysInSeconds = 30 * 24 * 60 * 60;

      // advance blockchain to loan end
      await ethers.provider.send('evm_increaseTime', [thirthyDaysInSeconds + 1]);

      // liquidate NFT
      await poolProxy.connect(randomUser).liquidateLoan(tokenId, borrower.address);

      expect(await tokenContract.ownerOf(tokenId)).to.be.equal(
        dutchAuctionLiquidatorFactory.address,
      );

      // Try to liquidate again
      await expect(
        poolProxy.connect(randomUser).liquidateLoan(tokenId, borrower.address),
      ).to.be.revertedWith('Pool: loan is closed');
    });

    it('should not be able to liquidate NFT if loan paiment is not late', async () => {
      const {
        poolProxy,
        impersonatedWhaleSigner,
        initialDailyInterestRateInBps,
        seaportSettlementManager,
        loanToValueInBps,
        collectionAddress,
        oracleSigner,
        randomUser,
        borrower,
      } = await buildTestContext();

      const { tokenId, orderExtraData, loanTimestamp, nftPrice } = await buyNFTPreparationHelper();

      const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

      // deposit into pool
      const deposit = ethers.utils.parseEther('100');
      await poolProxy
        .connect(impersonatedWhaleSigner)
        .depositNativeTokens(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
          value: deposit,
        });

      const loanDurationInDays = 30;
      const loanDurationInSeconds = loanDurationInDays * 24 * 60 * 60;

      // remaining to be paid
      const remainingToBePaid = nftPrice - ltvValue;

      const remainingToBePaidInBN = BigNumber.from(remainingToBePaid.toString());

      // calculate LoanPrice from NFT price
      const [loanPrice] = await poolProxy.calculateLoanPrice(
        remainingToBePaidInBN,
        loanDurationInDays,
      );

      const priceWithInterest = loanPrice.add(BigNumber.from(ltvValue.toString()));

      const oracleSignature = await mockSignLoan(
        collectionAddress,
        tokenId,
        BigNumber.from(nftPrice.toString()),
        priceWithInterest,
        borrower.address,
        0,
        loanTimestamp,
        orderExtraData,
        oracleSigner,
      );

      // buy NFT
      await buyNFTHelper(
        poolProxy,
        borrower,
        collectionAddress,
        tokenId,
        BigNumber.from(nftPrice.toString()),
        priceWithInterest,
        seaportSettlementManager,
        loanTimestamp,
        loanDurationInSeconds,
        orderExtraData,
        oracleSignature,
        BigNumber.from(ltvValue.toString()),
      );

      const thirthyDaysInSeconds = 20 * 24 * 60 * 60;

      // advance blockchain to less than next paiement which is 30 days
      await ethers.provider.send('evm_increaseTime', [thirthyDaysInSeconds - 1]);

      // try liquidating NFT
      await expect(
        poolProxy.connect(randomUser).liquidateLoan(tokenId, borrower.address),
      ).to.be.revertedWith('Pool: loan paiement not late');
    });

    it('should revert when trying to liquidate a loan that is already paid back', async () => {
      const {
        poolProxy,
        impersonatedWhaleSigner,
        initialDailyInterestRateInBps,
        seaportSettlementManager,
        loanToValueInBps,
        collectionAddress,
        oracleSigner,
        borrower,
        tokenContract,
        dutchAuctionLiquidatorFactory,
        randomUser,
      } = await buildTestContext();

      const { tokenId, orderExtraData, loanTimestamp, nftPrice } = await buyNFTPreparationHelper();

      const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

      // deposit into pool
      const deposit = ethers.utils.parseEther('100');
      await poolProxy
        .connect(impersonatedWhaleSigner)
        .depositNativeTokens(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
          value: deposit,
        });

      const loanDurationInDays = 30;
      const loanDurationInSeconds = loanDurationInDays * 24 * 60 * 60;

      // remaining to be paid
      const remainingToBePaid = nftPrice - ltvValue;

      const remainingToBePaidInBN = BigNumber.from(remainingToBePaid.toString());

      // calculate LoanPrice from NFT price
      const [loanPrice] = await poolProxy.calculateLoanPrice(
        remainingToBePaidInBN,
        loanDurationInDays,
      );

      const priceWithInterest = loanPrice.add(BigNumber.from(ltvValue.toString()));

      const oracleSignature = await mockSignLoan(
        collectionAddress,
        tokenId,
        BigNumber.from(nftPrice.toString()),
        priceWithInterest,
        borrower.address,
        0,
        loanTimestamp,
        orderExtraData,
        oracleSigner,
      );

      // buy NFT
      await buyNFTHelper(
        poolProxy,
        borrower,
        collectionAddress,
        tokenId,
        BigNumber.from(nftPrice.toString()),
        priceWithInterest,
        seaportSettlementManager,
        loanTimestamp,
        loanDurationInSeconds,
        orderExtraData,
        oracleSignature,
        BigNumber.from(ltvValue.toString()),
      );

      // repay loan
      await poolProxy.connect(borrower).refundLoan(tokenId, borrower.address, { value: loanPrice });

      // advance blockchain to loan end
      await ethers.provider.send('evm_increaseTime', [loanDurationInSeconds + 1]);

      // liquidate NFT
      await expect(
        poolProxy.connect(randomUser).liquidateLoan(tokenId, borrower.address),
      ).to.be.revertedWith('Pool: loan is closed');

      // new owner should be borrower
      expect(await tokenContract.ownerOf(tokenId)).to.be.equal(borrower.address);
    });

    it('should be able to liquidate NFT if loan is not paid before end of next paiement (30 days)', async () => {
      const {
        poolProxy,
        impersonatedWhaleSigner,
        initialDailyInterestRateInBps,
        seaportSettlementManager,
        loanToValueInBps,
        collectionAddress,
        oracleSigner,
        borrower,
        tokenContract,
        dutchAuctionLiquidatorFactory,
        randomUser,
      } = await buildTestContext();

      const { tokenId, orderExtraData, loanTimestamp, nftPrice } = await buyNFTPreparationHelper();

      const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

      // deposit into pool
      const deposit = ethers.utils.parseEther('100');
      await poolProxy
        .connect(impersonatedWhaleSigner)
        .depositNativeTokens(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
          value: deposit,
        });

      const loanDurationInDays = 90;
      const loanDurationInSeconds = loanDurationInDays * 24 * 60 * 60;

      // remaining to be paid
      const remainingToBePaid = nftPrice - ltvValue;

      const remainingToBePaidInBN = BigNumber.from(remainingToBePaid.toString());

      // calculate LoanPrice from NFT price
      const [loanPrice] = await poolProxy.calculateLoanPrice(
        remainingToBePaidInBN,
        loanDurationInDays,
      );

      const priceWithInterest = loanPrice.add(BigNumber.from(ltvValue.toString()));

      const oracleSignature = await mockSignLoan(
        collectionAddress,
        tokenId,
        BigNumber.from(nftPrice.toString()),
        priceWithInterest,
        borrower.address,
        0,
        loanTimestamp,
        orderExtraData,
        oracleSigner,
      );

      // buy NFT
      await buyNFTHelper(
        poolProxy,
        borrower,
        collectionAddress,
        tokenId,
        BigNumber.from(nftPrice.toString()),
        priceWithInterest,
        seaportSettlementManager,
        loanTimestamp,
        loanDurationInSeconds,
        orderExtraData,
        oracleSignature,
        BigNumber.from(ltvValue.toString()),
      );

      const thirthyDaysInSeconds = 30 * 24 * 60 * 60;

      // advance blockchain to loan end
      await ethers.provider.send('evm_increaseTime', [thirthyDaysInSeconds + 1]);

      // liquidate NFT
      await poolProxy.connect(randomUser).liquidateLoan(tokenId, borrower.address);

      expect(await tokenContract.ownerOf(tokenId)).to.be.equal(
        dutchAuctionLiquidatorFactory.address,
      );
    });

    it('should be able to liquidate NFT if loan is not paid before end of loan', async () => {
      const {
        poolProxy,
        impersonatedWhaleSigner,
        initialDailyInterestRateInBps,
        seaportSettlementManager,
        loanToValueInBps,
        collectionAddress,
        oracleSigner,
        borrower,
        tokenContract,
        dutchAuctionLiquidatorFactory,
        randomUser,
      } = await buildTestContext();

      const { tokenId, orderExtraData, loanTimestamp, nftPrice } = await buyNFTPreparationHelper();

      const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

      // deposit into pool
      const deposit = ethers.utils.parseEther('100');
      await poolProxy
        .connect(impersonatedWhaleSigner)
        .depositNativeTokens(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
          value: deposit,
        });

      const loanDurationInDays = 30;
      const loanDurationInSeconds = loanDurationInDays * 24 * 60 * 60;

      // remaining to be paid
      const remainingToBePaid = nftPrice - ltvValue;

      const remainingToBePaidInBN = BigNumber.from(remainingToBePaid.toString());

      // calculate LoanPrice from NFT price
      const [loanPrice] = await poolProxy.calculateLoanPrice(
        remainingToBePaidInBN,
        loanDurationInDays,
      );

      const priceWithInterest = loanPrice.add(BigNumber.from(ltvValue.toString()));

      const oracleSignature = await mockSignLoan(
        collectionAddress,
        tokenId,
        BigNumber.from(nftPrice.toString()),
        priceWithInterest,
        borrower.address,
        0,
        loanTimestamp,
        orderExtraData,
        oracleSigner,
      );

      // buy NFT
      await buyNFTHelper(
        poolProxy,
        borrower,
        collectionAddress,
        tokenId,
        BigNumber.from(nftPrice.toString()),
        priceWithInterest,
        seaportSettlementManager,
        loanTimestamp,
        loanDurationInSeconds,
        orderExtraData,
        oracleSignature,
        BigNumber.from(ltvValue.toString()),
      );

      // advance blockchain to loan end
      await ethers.provider.send('evm_increaseTime', [loanDurationInSeconds + 1]);

      // liquidate NFT
      await poolProxy.connect(randomUser).liquidateLoan(tokenId, borrower.address);

      expect(await tokenContract.ownerOf(tokenId)).to.be.equal(
        dutchAuctionLiquidatorFactory.address,
      );
    });
  });
});
