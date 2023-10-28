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
    const [
      poolFactoryOwner,
      protocolFeeCollector,
      proxyAdmin,
      oracleSigner,
      borrower,
      randomUser,
      lender1,
      lender2,
    ] = await ethers.getSigners();

    const ethWhale = '0xda9dfa130df4de4673b89022ee50ff26f6ea73cf';
    const impersonatedWhaleSigner = await ethers.getImpersonatedSigner(ethWhale);

    const minimalDepositAtCreation = ethers.utils.parseEther('1');

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
    await poolFactoryProxy.initialize(
      poolFactoryOwner.address,
      protocolFeeCollector.address,
      minimalDepositAtCreation,
    );

    // deploy liquidator
    const randomLiquidatorAddress = ethers.utils.hexlify(ethers.utils.randomBytes(20));
    const DutchAuctionLiquidatoFactory = await ethers.getContractFactory('DutchAuctionLiquidator');
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
    await poolFactoryProxy.updateAllowedLTVs([loanToValueInBps]);

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
      { value: minimalDepositAtCreation },
    );

    await poolFactoryProxy.createPool(
      collectionAddress,
      ethers.constants.AddressZero,
      loanToValueInBps,
      initialDailyInterestRateInBps,
      initialDeposit,
      nftFilterAddress,
      dutchAuctionLiquidatorFactory.address,
      { value: minimalDepositAtCreation },
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
      lender1,
      lender2,
      protocolFeeCollector,
    };
  };

  it('should have the correct version', async () => {
    const { poolProxy } = await buildTestContext();

    expect(await poolProxy.VERSION()).to.equal('1.0.0');
  });

  describe('Borrower', async () => {
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

        const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
          await buyNFTPreparationHelper();

        const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

        // deposit into pool
        const deposit = ethers.utils.parseEther('100');
        await poolProxy
          .connect(impersonatedWhaleSigner)
          .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
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

      it('should revert when trying to buy NFT with a duration of less than a day', async () => {
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

        const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
          await buyNFTPreparationHelper();

        const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

        // deposit into pool
        const deposit = ethers.utils.parseEther('100');
        await poolProxy
          .connect(impersonatedWhaleSigner)
          .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
            value: deposit,
          });

        const oracleSignature = await mockSignLoan(
          collectionAddress,
          tokenId,
          BigNumber.from(nftPrice.toString()),
          BigNumber.from(nftPrice.toString()),
          borrower.address,
          0,
          loanTimestamp,
          orderExtraData,
          oracleSigner,
        );

        // try to buy NFT with a duration of less than a day
        await expect(
          buyNFTHelper(
            poolProxy,
            borrower,
            collectionAddress,
            tokenId,
            BigNumber.from(nftPrice.toString()),
            BigNumber.from(nftPrice.toString()),
            seaportSettlementManager,
            loanTimestamp,
            0,
            orderExtraData,
            oracleSignature,
            BigNumber.from(ltvValue.toString()),
          ),
        ).to.be.revertedWith('Pool: loan duration too short');
      });

      it('should revert when trying to buy NFT with a duration of more than 90 days', async () => {
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

        const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
          await buyNFTPreparationHelper();

        const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

        // deposit into pool
        const deposit = ethers.utils.parseEther('100');
        await poolProxy
          .connect(impersonatedWhaleSigner)
          .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
            value: deposit,
          });

        const oracleSignature = await mockSignLoan(
          collectionAddress,
          tokenId,
          BigNumber.from(nftPrice.toString()),
          BigNumber.from(nftPrice.toString()),
          borrower.address,
          0,
          loanTimestamp,
          orderExtraData,
          oracleSigner,
        );

        const ninetyOneDaysInSeconds = 91 * 24 * 60 * 60;

        // try to buy NFT with a duration of less than a day
        await expect(
          buyNFTHelper(
            poolProxy,
            borrower,
            collectionAddress,
            tokenId,
            BigNumber.from(nftPrice.toString()),
            BigNumber.from(nftPrice.toString()),
            seaportSettlementManager,
            loanTimestamp,
            ninetyOneDaysInSeconds,
            orderExtraData,
            oracleSignature,
            BigNumber.from(ltvValue.toString()),
          ),
        ).to.be.revertedWith('Pool: loan duration too long');
      });

      it('should revert when trying to buy NFT with too low LTV', async () => {
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

        const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
          await buyNFTPreparationHelper();

        const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

        // deposit into pool
        const deposit = ethers.utils.parseEther('100');
        await poolProxy
          .connect(impersonatedWhaleSigner)
          .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
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

        await expect(
          poolProxy
            .connect(borrower)
            .buyNFT(
              collectionAddress,
              tokenId,
              BigNumber.from(nftPrice.toString()),
              BigNumber.from(priceWithInterest.toString()),
              seaportSettlementManager.address,
              loanTimestamp,
              loanDurationInSeconds,
              orderExtraData,
              oracleSignature,
              { value: BigNumber.from(ltvValue.toString()).sub(1) },
            ),
        ).to.be.revertedWith('Pool: LTV not respected');
      });

      it('should revert when the oracle Signature is wrong', async () => {
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

        const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
          await buyNFTPreparationHelper();

        const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

        // deposit into pool
        const deposit = ethers.utils.parseEther('100');
        await poolProxy
          .connect(impersonatedWhaleSigner)
          .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
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
          loanTimestamp + 1, // change loanTimestamp to make signature invalid
          orderExtraData,
          oracleSigner,
        );

        await expect(
          poolProxy
            .connect(borrower)
            .buyNFT(
              collectionAddress,
              tokenId,
              BigNumber.from(nftPrice.toString()),
              BigNumber.from(priceWithInterest.toString()),
              seaportSettlementManager.address,
              loanTimestamp,
              loanDurationInSeconds,
              orderExtraData,
              oracleSignature,
              { value: BigNumber.from(ltvValue.toString()) },
            ),
        ).to.be.revertedWith('Pool: NFT loan not accepted');
      });

      it('should revert when the signer of the oracle is wrong', async () => {
        const {
          poolProxy,
          impersonatedWhaleSigner,
          initialDailyInterestRateInBps,
          seaportSettlementManager,
          loanToValueInBps,
          collectionAddress,
          randomUser,
          borrower,
        } = await buildTestContext();

        const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
          await buyNFTPreparationHelper();

        const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

        // deposit into pool
        const deposit = ethers.utils.parseEther('100');
        await poolProxy
          .connect(impersonatedWhaleSigner)
          .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
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
          randomUser, // should not be able to sign
        );

        await expect(
          poolProxy
            .connect(borrower)
            .buyNFT(
              collectionAddress,
              tokenId,
              BigNumber.from(nftPrice.toString()),
              BigNumber.from(priceWithInterest.toString()),
              seaportSettlementManager.address,
              loanTimestamp,
              loanDurationInSeconds,
              orderExtraData,
              oracleSignature,
              { value: BigNumber.from(ltvValue.toString()) },
            ),
        ).to.be.revertedWith('Pool: NFT loan not accepted');
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
          .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
            value: secondDeposit,
          });

        const poolProxyBalanceAfter = await ethers.provider.getBalance(poolProxy.address);

        expect(poolProxyBalanceAfter).to.equal(poolProxyBalanceBefore.add(secondDeposit));
      });
    });

    describe('Liquidation', async () => {
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

        const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
          await buyNFTPreparationHelper();

        const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

        // deposit into pool
        const deposit = ethers.utils.parseEther('100');
        await poolProxy
          .connect(impersonatedWhaleSigner)
          .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
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
        await ethers.provider.send('evm_mine', []);

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

        const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
          await buyNFTPreparationHelper();

        const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

        // deposit into pool
        const deposit = ethers.utils.parseEther('100');
        await poolProxy
          .connect(impersonatedWhaleSigner)
          .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
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
        await ethers.provider.send('evm_mine', []);

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

        const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
          await buyNFTPreparationHelper();

        const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

        // deposit into pool
        const deposit = ethers.utils.parseEther('100');
        await poolProxy
          .connect(impersonatedWhaleSigner)
          .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
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
        await poolProxy
          .connect(borrower)
          .refundLoan(tokenId, borrower.address, { value: loanPrice });

        // advance blockchain to loan end
        await ethers.provider.send('evm_increaseTime', [loanDurationInSeconds + 1]);
        await ethers.provider.send('evm_mine', []);

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

        const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
          await buyNFTPreparationHelper();

        const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

        // deposit into pool
        const deposit = ethers.utils.parseEther('100');
        await poolProxy
          .connect(impersonatedWhaleSigner)
          .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
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
        await ethers.provider.send('evm_mine', []);

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

        const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
          await buyNFTPreparationHelper();

        const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

        // deposit into pool
        const deposit = ethers.utils.parseEther('100');
        await poolProxy
          .connect(impersonatedWhaleSigner)
          .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
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
        await ethers.provider.send('evm_mine', []);

        // liquidate NFT
        await poolProxy.connect(randomUser).liquidateLoan(tokenId, borrower.address);

        expect(await tokenContract.ownerOf(tokenId)).to.be.equal(
          dutchAuctionLiquidatorFactory.address,
        );
      });
    });
    describe('Refund loan', async () => {
      it('should be able to refund loan', async () => {
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

        const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
          await buyNFTPreparationHelper();

        const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

        // deposit into pool
        const deposit = ethers.utils.parseEther('100');
        await poolProxy
          .connect(impersonatedWhaleSigner)
          .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
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

        // expect wrapped NFT to be owned by borrower
        const wrappedTokenAddress = await poolProxy.wrappedNFT();
        const wrappedTokenContract = await ethers.getContractAt('ERC721', wrappedTokenAddress);
        expect(await wrappedTokenContract.ownerOf(tokenId)).to.be.equal(borrower.address);

        // advance blockchain 29 days
        await ethers.provider.send('evm_increaseTime', [29 * 24 * 60 * 60]);
        await ethers.provider.send('evm_mine', []);

        // refund loan of loanPrice / 3 (1/3 of loan price)
        const firstRefund = await poolProxy
          .connect(borrower)
          .refundLoan(tokenId, borrower.address, {
            value: loanPrice.div(3),
          });

        await expect(firstRefund)
          .emit(poolProxy, 'LoanPartiallyRefunded')
          .withArgs(
            ethers.utils.getAddress(collectionAddress),
            tokenId,
            ethers.utils.getAddress(borrower.address),
            loanPrice.div(3),
            loanPrice.sub(loanPrice.div(3)),
          );

        // advance blockchain 29 days
        await ethers.provider.send('evm_increaseTime', [29 * 24 * 60 * 60]);
        await ethers.provider.send('evm_mine', []);

        // refund loan of loanPrice / 3 (1/3 of loan price)
        await poolProxy.connect(borrower).refundLoan(tokenId, borrower.address, {
          value: loanPrice.div(3),
        });

        // advance blockchain 29 days
        await ethers.provider.send('evm_increaseTime', [29 * 24 * 60 * 60]);
        await ethers.provider.send('evm_mine', []);

        // refund loan of loanPrice / 3 (1/3 of loan price)
        const finalRefund = await poolProxy
          .connect(borrower)
          .refundLoan(tokenId, borrower.address, {
            value: loanPrice.div(3),
          });

        await expect(finalRefund)
          .emit(poolProxy, 'LoanEntirelyRefunded')
          .withArgs(
            ethers.utils.getAddress(collectionAddress),
            tokenId,
            ethers.utils.getAddress(borrower.address),
            priceWithInterest,
          );

        // verify that loan is paid back
        const loan = await poolProxy.retrieveLoan(tokenId, borrower.address);
        expect(loan.amountOwedWithInterest).to.be.equal(0);

        // verify that loan is closed
        expect(loan.isClosed).to.be.true;

        // expect wrapped NFT to be burnt
        await expect(wrappedTokenContract.ownerOf(tokenId)).to.be.revertedWith(
          'ERC721: invalid token ID',
        );

        // verify that NFT is back to borrower
        const tokenContract = await ethers.getContractAt('ERC721', collectionAddress);
        expect(await tokenContract.ownerOf(tokenId)).to.be.equal(borrower.address);
      });

      it('should revert when trying to refund a non-existent loan', async () => {
        const { poolProxy, borrower, randomUser } = await buildTestContext();

        // generate random number between 1 and 1000
        const randomTokenId = Math.floor(Math.random() * 1000) + 1;

        await expect(
          poolProxy.connect(randomUser).refundLoan(randomTokenId, borrower.address, {
            value: ethers.utils.parseEther('1'),
          }),
        ).to.be.revertedWith('Pool: loan does not exist');
      });

      it('should revert when trying to refund a loan already paid back', async () => {
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

        const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
          await buyNFTPreparationHelper();

        const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

        // deposit into pool
        const deposit = ethers.utils.parseEther('100');
        await poolProxy
          .connect(impersonatedWhaleSigner)
          .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
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

        await poolProxy.connect(borrower).refundLoan(tokenId, borrower.address, {
          value: loanPrice,
        });

        // Act & Assert: Expect a revert
        await expect(
          poolProxy.connect(borrower).refundLoan(tokenId, borrower.address),
        ).to.be.revertedWith('Pool: loan is closed');
      });

      it('should revert when sending an incorrect refund amount (not enough)', async () => {
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

        const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
          await buyNFTPreparationHelper();

        const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

        // deposit into pool
        const deposit = ethers.utils.parseEther('100');
        await poolProxy
          .connect(impersonatedWhaleSigner)
          .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
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

        await expect(
          poolProxy.connect(borrower).refundLoan(tokenId, borrower.address, {
            value: loanPrice.sub(1), // substracting 1 wei to the refund and expecting a revert,
          }),
        ).to.be.revertedWith('Pool: msg.value not equal to next payment');
      });

      it('should revert when sending an incorrect refund amount (too much)', async () => {
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

        const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
          await buyNFTPreparationHelper();

        const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

        // deposit into pool
        const deposit = ethers.utils.parseEther('100');
        await poolProxy
          .connect(impersonatedWhaleSigner)
          .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
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

        await expect(
          poolProxy.connect(borrower).refundLoan(tokenId, borrower.address, {
            value: loanPrice.add(1), // adding 1 wei to the refund and expecting a revert,
          }),
        ).to.be.revertedWith('Pool: msg.value not equal to next payment');
      });

      it('should revert when trying to refund an expired loan', async () => {
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

        const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
          await buyNFTPreparationHelper();

        const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

        // deposit into pool
        const deposit = ethers.utils.parseEther('100');
        await poolProxy
          .connect(impersonatedWhaleSigner)
          .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
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
        await ethers.provider.send('evm_increaseTime', [loanDurationInSeconds]);
        await ethers.provider.send('evm_mine', []);

        await expect(
          poolProxy.connect(borrower).refundLoan(tokenId, borrower.address, {
            value: loanPrice, // adding 1 wei to the refund and expecting a revert,
          }),
        ).to.be.revertedWith('Pool: loan expired');
      });
    });
  });
  describe('Lender', async () => {
    describe('When Depositing Native Tokens', async () => {
      it('should mint shares', async () => {
        const { poolProxy, initialDailyInterestRateInBps, lender1 } = await buildTestContext();

        const lender1SharesBefore = await poolProxy.balanceOf(lender1.address);
        expect(lender1SharesBefore).to.be.equal(0);

        const lendingValue = ethers.utils.parseEther('100');

        const lendTx = await poolProxy
          .connect(lender1)
          .depositAndVote(lender1.address, initialDailyInterestRateInBps, {
            value: lendingValue,
          });

        const previewDepositShare = await poolProxy.previewDeposit(lendingValue);

        await expect(lendTx)
          .to.emit(poolProxy, 'Deposit')
          .withArgs(lender1.address, lender1.address, lendingValue, previewDepositShare);

        const lender1SharesAfter = await poolProxy.balanceOf(lender1.address);
        expect(lender1SharesAfter).to.be.equal(previewDepositShare);
      });

      it('should be able to redeem (after vesting time)', async () => {
        const { poolProxy, initialDailyInterestRateInBps, lender1 } = await buildTestContext();

        const depositAmount = ethers.utils.parseEther('100');
        await poolProxy
          .connect(lender1)
          .depositAndVote(lender1.address, initialDailyInterestRateInBps, {
            value: depositAmount,
          });

        const twelveHoursInSeconds = 12 * 60 * 60;
        const vestingTime = twelveHoursInSeconds * initialDailyInterestRateInBps;

        // advance blockchain to vesting time
        await ethers.provider.send('evm_increaseTime', [vestingTime]);
        await ethers.provider.send('evm_mine', []);

        const lender1BalanceBeforeWithdraw = await ethers.provider.getBalance(lender1.address);

        const lender1Shares = await poolProxy.balanceOf(lender1.address);
        const lender1Assets = await poolProxy.previewRedeem(lender1Shares);

        const withdrawTx = await poolProxy
          .connect(lender1)
          .redeem(lender1Shares, lender1.address, lender1.address);
        expect(withdrawTx)
          .to.emit(poolProxy, 'Withdraw')
          .withArgs(
            lender1.address,
            lender1.address,
            lender1.address,
            lender1Assets,
            lender1Shares,
          );

        const lender1SharesAfter = await poolProxy.balanceOf(lender1.address);
        expect(lender1SharesAfter).to.be.equal(0);

        const lender1BalanceAfterWithdraw = await ethers.provider.getBalance(lender1.address);
        expect(lender1BalanceAfterWithdraw).to.be.greaterThan(lender1BalanceBeforeWithdraw);
      });

      it('should be able to withdraw (after vesting time)', async () => {
        const { poolProxy, initialDailyInterestRateInBps, lender1 } = await buildTestContext();

        const depositAmount = ethers.utils.parseEther('100');
        await poolProxy
          .connect(lender1)
          .depositAndVote(lender1.address, initialDailyInterestRateInBps, {
            value: depositAmount,
          });

        const twelveHoursInSeconds = 12 * 60 * 60;
        const vestingTime = twelveHoursInSeconds * initialDailyInterestRateInBps;

        // advance blockchain to vesting time
        await ethers.provider.send('evm_increaseTime', [vestingTime]);
        await ethers.provider.send('evm_mine', []);

        const lender1BalanceBeforeWithdraw = await ethers.provider.getBalance(lender1.address);

        const lender1Assets = await poolProxy.maxWithdrawAvailable(lender1.address);
        const lender1Shares = await poolProxy.balanceOf(lender1.address);

        const withdrawTx = await poolProxy
          .connect(lender1)
          .withdraw(lender1Assets, lender1.address, lender1.address);

        expect(withdrawTx)
          .to.emit(poolProxy, 'Withdraw')
          .withArgs(
            lender1.address,
            lender1.address,
            lender1.address,
            lender1Assets,
            lender1Shares,
          );

        const lender1SharesAfter = await poolProxy.balanceOf(lender1.address);
        expect(lender1SharesAfter).to.be.equal(0);

        const lender1BalanceAfterWithdraw = await ethers.provider.getBalance(lender1.address);
        expect(lender1BalanceAfterWithdraw).to.be.greaterThan(lender1BalanceBeforeWithdraw);
      });

      it('vesting time should increase when depositing with a higher interest rate', async () => {
        const { poolProxy, initialDailyInterestRateInBps, lender1 } = await buildTestContext();

        const depositAmount = ethers.utils.parseEther('100');
        await poolProxy
          .connect(lender1)
          .depositAndVote(lender1.address, initialDailyInterestRateInBps, {
            value: depositAmount,
          });

        const vestingTimeBefore = await poolProxy.vestingTimePerLender(lender1.address);

        await poolProxy
          .connect(lender1)
          .depositAndVote(lender1.address, initialDailyInterestRateInBps + 1, {
            value: depositAmount,
          });

        const vestingTimeAfter = await poolProxy.vestingTimePerLender(lender1.address);

        expect(vestingTimeAfter).to.be.greaterThan(vestingTimeBefore);
      });

      it('vesting time should not decrease when depositing with a lower interest rate', async () => {
        const { poolProxy, initialDailyInterestRateInBps, lender1 } = await buildTestContext();

        const depositAmount = ethers.utils.parseEther('100');
        await poolProxy
          .connect(lender1)
          .depositAndVote(lender1.address, initialDailyInterestRateInBps, {
            value: depositAmount,
          });

        const vestingTimeBefore = await poolProxy.vestingTimePerLender(lender1.address);

        await poolProxy
          .connect(lender1)
          .depositAndVote(lender1.address, initialDailyInterestRateInBps - 1, {
            value: depositAmount,
          });

        const vestingTimeAfter = await poolProxy.vestingTimePerLender(lender1.address);

        expect(vestingTimeAfter).to.be.equal(vestingTimeBefore);
      });

      // this test is a bit weird as it will not be always the case (some refund or liquidation could happen before depositing)
      it('should return number of shares returned by previewDeposit', async () => {
        const { poolProxy, initialDailyInterestRateInBps, lender1 } = await buildTestContext();

        const depositAmount = ethers.utils.parseEther('100');

        const lender1SharesBefore = await poolProxy.balanceOf(lender1.address);

        const lender1SharesPreview = await poolProxy.previewDeposit(depositAmount);

        expect(lender1SharesPreview).to.not.be.equal(0);

        const tx = await poolProxy
          .connect(lender1)
          .depositAndVote(lender1.address, initialDailyInterestRateInBps, {
            value: depositAmount,
          });

        const receipt = await tx.wait();

        const lender1SharesAfter = await poolProxy.balanceOf(lender1.address);

        expect(lender1SharesPreview).to.be.equal(lender1SharesAfter.sub(lender1SharesBefore));
      });

      it('should revert if interest daily rate is too high', async () => {
        const { poolProxy, lender1 } = await buildTestContext();

        const depositAmount = ethers.utils.parseEther('100');

        const maxInterestRate = await poolProxy.maxDailyInterestRate();

        await expect(
          poolProxy.connect(lender1).depositAndVote(lender1.address, maxInterestRate.add(1), {
            value: depositAmount,
          }),
        ).to.be.revertedWith('Pool: daily interest rate too high');
      });

      it('should revert if trying to withdraw before vesting time', async () => {
        const { poolProxy, initialDailyInterestRateInBps, lender1 } = await buildTestContext();

        const depositAmount = ethers.utils.parseEther('100');
        await poolProxy
          .connect(lender1)
          .depositAndVote(lender1.address, initialDailyInterestRateInBps, {
            value: depositAmount,
          });

        const twelveHoursInSeconds = 12 * 60 * 60;
        const vestingTime = twelveHoursInSeconds * initialDailyInterestRateInBps;

        // advance blockchain to vesting time - 1
        await ethers.provider.send('evm_increaseTime', [vestingTime - 100]);
        await ethers.provider.send('evm_mine', []);

        const lender1Shares = await poolProxy.balanceOf(lender1.address);

        await expect(
          poolProxy.connect(lender1).redeem(lender1Shares, lender1.address, lender1.address),
        ).to.be.revertedWith('Pool: vesting time not respected');
      });

      describe('when two lenders deposit', async () => {
        it('lender1 vesting time should not be impacted by lender2 deposit', async () => {
          const { poolProxy, initialDailyInterestRateInBps, lender1, lender2 } =
            await buildTestContext();

          const depositAmount = ethers.utils.parseEther('100');
          await poolProxy
            .connect(lender1)
            .depositAndVote(lender1.address, initialDailyInterestRateInBps, {
              value: depositAmount,
            });

          const vestingTimeLender1Before = await poolProxy.vestingTimePerLender(lender1.address);

          await poolProxy
            .connect(lender2)
            .depositAndVote(lender2.address, initialDailyInterestRateInBps * 2, {
              value: depositAmount,
            });

          const vestingTimeLender1After = await poolProxy.vestingTimePerLender(lender1.address);

          expect(vestingTimeLender1After).to.be.equal(vestingTimeLender1Before);
        });

        it('when lender2 deposit with a lower interest rate, dailyInterestRate should decrease', async () => {
          const { poolProxy, initialDailyInterestRateInBps, lender1, lender2 } =
            await buildTestContext();

          const depositAmount = ethers.utils.parseEther('100');

          await poolProxy
            .connect(lender1)
            .depositAndVote(lender1.address, initialDailyInterestRateInBps, {
              value: depositAmount,
            });

          const dailyInterestRateBefore = await poolProxy.dailyInterestRate();

          await poolProxy
            .connect(lender2)
            .depositAndVote(lender2.address, initialDailyInterestRateInBps * 0.5, {
              value: depositAmount,
            });

          const dailyInterestRateAfter = await poolProxy.dailyInterestRate();

          expect(dailyInterestRateAfter).to.be.lessThan(dailyInterestRateBefore);
        });

        it('when lender2 deposit with a higher interest rate, dailyInterestRate should increase', async () => {
          const { poolProxy, initialDailyInterestRateInBps, lender1, lender2 } =
            await buildTestContext();

          const depositAmount = ethers.utils.parseEther('100');

          await poolProxy
            .connect(lender1)
            .depositAndVote(lender1.address, initialDailyInterestRateInBps, {
              value: depositAmount,
            });

          const dailyInterestRateBefore = await poolProxy.dailyInterestRate();

          await poolProxy
            .connect(lender2)
            .depositAndVote(lender2.address, initialDailyInterestRateInBps * 2, {
              value: depositAmount,
            });

          const dailyInterestRateAfter = await poolProxy.dailyInterestRate();

          expect(dailyInterestRateAfter).to.be.greaterThan(dailyInterestRateBefore);
        });
      });
      describe('when loans are emitted', async () => {
        it('should increase lp tokens price when loan is paid back', async () => {
          const {
            poolProxy,
            impersonatedWhaleSigner,
            initialDailyInterestRateInBps,
            seaportSettlementManager,
            loanToValueInBps,
            collectionAddress,
            oracleSigner,
            borrower,
            lender1,
          } = await buildTestContext();

          const depositAmount = ethers.utils.parseEther('100');
          await poolProxy
            .connect(lender1)
            .depositAndVote(lender1.address, initialDailyInterestRateInBps, {
              value: depositAmount,
            });

          const balanceOfLpTokens = await poolProxy.balanceOf(lender1.address);

          const redeemValueBefore = await poolProxy.previewRedeem(balanceOfLpTokens);

          // generate loan and repay it
          const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
            await buyNFTPreparationHelper();

          const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

          // deposit into pool
          const deposit = ethers.utils.parseEther('100');
          await poolProxy
            .connect(impersonatedWhaleSigner)
            .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
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

          // advance blockchain 29 days
          await ethers.provider.send('evm_increaseTime', [29 * 24 * 60 * 60]);
          await ethers.provider.send('evm_mine', []);

          // refund loan of loanPrice / 3 (1/3 of loan price)
          await poolProxy.connect(borrower).refundLoan(tokenId, borrower.address, {
            value: loanPrice,
          });

          // verify that loan is paid back
          const loan = await poolProxy.retrieveLoan(tokenId, borrower.address);
          expect(loan.amountOwedWithInterest).to.be.equal(0);

          const redeemValueAfter = await poolProxy.previewRedeem(balanceOfLpTokens);

          expect(redeemValueAfter).to.be.greaterThan(redeemValueBefore);
        });

        // if loan is not paid back, lp tokens price should decrease
        it('should decrease lp tokens price when loan is not paid back', async () => {
          const {
            poolProxy,
            impersonatedWhaleSigner,
            initialDailyInterestRateInBps,
            seaportSettlementManager,
            loanToValueInBps,
            collectionAddress,
            oracleSigner,
            borrower,
            lender1,
            dutchAuctionLiquidatorFactory,
          } = await buildTestContext();

          const depositAmount = ethers.utils.parseEther('100');
          await poolProxy
            .connect(lender1)
            .depositAndVote(lender1.address, initialDailyInterestRateInBps, {
              value: depositAmount,
            });

          const balanceOfLpTokens = await poolProxy.balanceOf(lender1.address);

          const redeemValueBefore = await poolProxy.previewRedeem(balanceOfLpTokens);

          // generate loan and repay it
          const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
            await buyNFTPreparationHelper();

          const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

          // deposit into pool
          const deposit = ethers.utils.parseEther('100');
          await poolProxy
            .connect(impersonatedWhaleSigner)
            .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
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

          // advance blockchain 31 days so we can liquidate the loan
          await ethers.provider.send('evm_increaseTime', [71 * 24 * 60 * 60]);
          await ethers.provider.send('evm_mine', []);

          const liquidator = await poolProxy.liquidator();

          // liquidate NFT
          const liquidtateTx = await poolProxy
            .connect(borrower)
            .liquidateLoan(tokenId, borrower.address);
          await expect(liquidtateTx)
            .to.emit(poolProxy, 'LoanLiquidated')
            .withArgs(
              ethers.utils.getAddress(collectionAddress),
              tokenId,
              ethers.utils.getAddress(borrower.address),
              ethers.utils.getAddress(liquidator),
              priceWithInterest,
            );

          // advance blockchain 70 days so we can liquidate the loan for a 0 price
          await ethers.provider.send('evm_increaseTime', [70 * 24 * 60 * 60]);
          await ethers.provider.send('evm_mine', []);

          const liquidatingPrice = await dutchAuctionLiquidatorFactory.getLiquidationCurrentPrice(
            collectionAddress,
            tokenId,
          );
          expect(liquidatingPrice).to.be.equal(0);

          // buy NFT for 0
          const buyTx = await dutchAuctionLiquidatorFactory.buy(collectionAddress, tokenId);
          expect(buyTx)
            .emit(poolProxy, 'LoanLiquidationRefund')
            .withArgs(ethers.utils.getAddress(collectionAddress), tokenId, 0);

          const redeemValueAfter = await poolProxy.previewRedeem(balanceOfLpTokens);
          expect(redeemValueAfter).to.be.lessThan(redeemValueBefore);
        });

        // if loan is liquidated at higher price that what is owed it should increase lp tokens price
        it('should increase lp tokens price when loan is liquidated at higher price', async () => {
          const {
            poolProxy,
            impersonatedWhaleSigner,
            initialDailyInterestRateInBps,
            seaportSettlementManager,
            loanToValueInBps,
            collectionAddress,
            oracleSigner,
            borrower,
            lender1,
            dutchAuctionLiquidatorFactory,
          } = await buildTestContext();

          const depositAmount = ethers.utils.parseEther('100');
          await poolProxy
            .connect(lender1)
            .depositAndVote(lender1.address, initialDailyInterestRateInBps, {
              value: depositAmount,
            });

          const balanceOfLpTokens = await poolProxy.balanceOf(lender1.address);

          const redeemValueBefore = await poolProxy.previewRedeem(balanceOfLpTokens);

          // generate loan and repay it
          const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
            await buyNFTPreparationHelper();

          const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

          // deposit into pool
          const deposit = ethers.utils.parseEther('100');
          await poolProxy
            .connect(impersonatedWhaleSigner)
            .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
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

          // advance blockchain 31 days so we can liquidate the loan
          await ethers.provider.send('evm_increaseTime', [30 * 24 * 60 * 60]);
          await ethers.provider.send('evm_mine', []);

          // liquidate NFT
          await poolProxy.connect(borrower).liquidateLoan(tokenId, borrower.address);

          // advance blockchain 1 days so we can liquidate the loan for a higher price that what owed
          await ethers.provider.send('evm_increaseTime', [1 * 24 * 60 * 60]);
          await ethers.provider.send('evm_mine', []);

          const liquidatingPrice = await dutchAuctionLiquidatorFactory.getLiquidationCurrentPrice(
            collectionAddress,
            tokenId,
          );

          // buy NFT for 0
          const buyTx = await dutchAuctionLiquidatorFactory.buy(collectionAddress, tokenId, {
            value: liquidatingPrice,
          });
          expect(buyTx)
            .emit(poolProxy, 'LoanLiquidationRefund')
            .withArgs(ethers.utils.getAddress(collectionAddress), tokenId, liquidatingPrice);

          const redeemValueAfter = await poolProxy.previewRedeem(balanceOfLpTokens);
          expect(redeemValueAfter).to.be.greaterThan(redeemValueBefore);
        });

        it('should decrease lp tokens price when loan is liquidated at lower price', async () => {
          const {
            poolProxy,
            impersonatedWhaleSigner,
            initialDailyInterestRateInBps,
            seaportSettlementManager,
            loanToValueInBps,
            collectionAddress,
            oracleSigner,
            borrower,
            lender1,
            dutchAuctionLiquidatorFactory,
          } = await buildTestContext();

          const depositAmount = ethers.utils.parseEther('100');
          await poolProxy
            .connect(lender1)
            .depositAndVote(lender1.address, initialDailyInterestRateInBps, {
              value: depositAmount,
            });

          const balanceOfLpTokens = await poolProxy.balanceOf(lender1.address);

          const redeemValueBefore = await poolProxy.previewRedeem(balanceOfLpTokens);

          // generate loan and repay it
          const { tokenId, orderExtraData, loanTimestamp, nftPrice } =
            await buyNFTPreparationHelper();

          const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

          // deposit into pool
          const deposit = ethers.utils.parseEther('100');
          await poolProxy
            .connect(impersonatedWhaleSigner)
            .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
              value: deposit,
            });

          const loanDurationInDays = 30;
          const loanDurationInSeconds = loanDurationInDays * 24 * 60 * 60;

          // remaining to be paid
          const remainingToBePaid = nftPrice - ltvValue;

          const remainingToBePaidInBN = BigNumber.from(remainingToBePaid.toString());

          // calculate LoanPrice from NFT price
          const [loanPrice, adjustedRemainingLoanAmountWithInterest] =
            await poolProxy.calculateLoanPrice(remainingToBePaidInBN, loanDurationInDays);

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

          // advance blockchain 31 days so we can liquidate the loan
          await ethers.provider.send('evm_increaseTime', [30 * 24 * 60 * 60]);
          await ethers.provider.send('evm_mine', []);

          // liquidate NFT
          await poolProxy.connect(borrower).liquidateLoan(tokenId, borrower.address);

          // advance blockchain 5 days so we can liquidate the loan for a lower price that whats owed
          await ethers.provider.send('evm_increaseTime', [5 * 24 * 60 * 60]);
          await ethers.provider.send('evm_mine', []);

          const liquidatingPrice = await dutchAuctionLiquidatorFactory.getLiquidationCurrentPrice(
            collectionAddress,
            tokenId,
          );
          expect(liquidatingPrice).to.be.greaterThan(adjustedRemainingLoanAmountWithInterest);

          // buy NFT for 0
          await dutchAuctionLiquidatorFactory.buy(collectionAddress, tokenId, {
            value: liquidatingPrice,
          });

          const redeemValueAfter = await poolProxy.previewRedeem(balanceOfLpTokens);
          expect(redeemValueAfter).to.be.lessThan(redeemValueBefore);
        });
      });
    });
  });
  describe('Protocol Fees', async () => {
    it('should be able to withdraw protocol fees', async () => {
      const {
        poolProxy,
        impersonatedWhaleSigner,
        initialDailyInterestRateInBps,
        seaportSettlementManager,
        loanToValueInBps,
        collectionAddress,
        oracleSigner,
        borrower,
        protocolFeeCollector,
      } = await buildTestContext();

      const { tokenId, orderExtraData, loanTimestamp, nftPrice } = await buyNFTPreparationHelper();

      const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

      // deposit into pool
      const deposit = ethers.utils.parseEther('100');
      await poolProxy
        .connect(impersonatedWhaleSigner)
        .depositAndVote(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
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

      // expect protocol fees to be 0 at the beginning
      const totalFeesCollectedBefore = await poolProxy.balanceOf(protocolFeeCollector.address);
      expect(totalFeesCollectedBefore).to.be.equal(0);

      // advance blockchain 29 days
      await ethers.provider.send('evm_increaseTime', [29 * 24 * 60 * 60]);
      await ethers.provider.send('evm_mine', []);

      // refund loan of loanPrice / 3 (1/3 of loan price)
      await poolProxy.connect(borrower).refundLoan(tokenId, borrower.address, {
        value: loanPrice.div(3),
      });

      // fetch loan info
      const loan = await poolProxy.retrieveLoan(tokenId, borrower.address);

      // expect protocol fees to be 15% of the loan.interestAmountPerPaiement
      const protocolFeesCalculated = loan.interestAmountPerPaiement.mul(15).div(100);

      // expect protocol fees to be 15% of the loan.interestAmountPerPaiement
      const totalFeesCollectedInShares = await poolProxy.balanceOf(protocolFeeCollector.address);
      const totalFeesCollectedInAssets = await poolProxy.previewRedeem(totalFeesCollectedInShares);

      // todo: use more meaningful delta
      const delta = ethers.utils.parseEther('0.1');
      expect(totalFeesCollectedInAssets).to.be.closeTo(protocolFeesCalculated, delta);

      // protocol fee collector balance before withdraw
      const protocolFeeCollectorBalanceBefore = await ethers.provider.getBalance(
        protocolFeeCollector.address,
      );

      // withdraw protocol fees
      const withdrawTx = await poolProxy
        .connect(protocolFeeCollector)
        .redeem(
          totalFeesCollectedInShares,
          protocolFeeCollector.address,
          protocolFeeCollector.address,
        );

      // expect protocol fees to be 0 after withdraw
      const totalFeesCollectedAfterWithdraw = await poolProxy.balanceOf(
        protocolFeeCollector.address,
      );
      expect(totalFeesCollectedAfterWithdraw).to.be.equal(0);

      // expect protocol fee collector to have the protocol fees
      const protocolFeeCollectorBalanceAfter = await ethers.provider.getBalance(
        protocolFeeCollector.address,
      );
      const txReceipt = await ethers.provider.getTransactionReceipt(withdrawTx.hash);

      const gasUsed = txReceipt.gasUsed.mul(withdrawTx.gasPrice as BigNumber);

      expect(protocolFeeCollectorBalanceAfter).to.be.equal(
        totalFeesCollectedInAssets.add(protocolFeeCollectorBalanceBefore).sub(gasUsed),
      );
    });

    it('should be able to withdraw protocol fees and lender liquidity', async () => {
      const {
        poolProxy,
        impersonatedWhaleSigner: lender,
        initialDailyInterestRateInBps,
        seaportSettlementManager,
        loanToValueInBps,
        collectionAddress,
        oracleSigner,
        borrower,
        protocolFeeCollector,
        poolFactoryOwner,
      } = await buildTestContext();

      const { tokenId, orderExtraData, loanTimestamp, nftPrice } = await buyNFTPreparationHelper();

      const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

      // deposit into pool
      const deposit = ethers.utils.parseEther('100');
      await poolProxy
        .connect(lender)
        .depositAndVote(lender.address, initialDailyInterestRateInBps, {
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

      // expect protocol fees to be 0 at the beginning
      const totalFeesCollectedBefore = await poolProxy.balanceOf(protocolFeeCollector.address);
      expect(totalFeesCollectedBefore).to.be.equal(0);

      // advance blockchain 29 days
      await ethers.provider.send('evm_increaseTime', [29 * 24 * 60 * 60]);
      await ethers.provider.send('evm_mine', []);

      // refund loan of loanPrice / 3 (1/3 of loan price)
      await poolProxy.connect(borrower).refundLoan(tokenId, borrower.address, {
        value: loanPrice.div(3),
      });

      // advance blockchain 29 days
      await ethers.provider.send('evm_increaseTime', [29 * 24 * 60 * 60]);
      await ethers.provider.send('evm_mine', []);

      // refund loan of loanPrice / 3 (1/3 of loan price)
      await poolProxy.connect(borrower).refundLoan(tokenId, borrower.address, {
        value: loanPrice.div(3),
      });

      // advance blockchain 29 days
      await ethers.provider.send('evm_increaseTime', [29 * 24 * 60 * 60]);
      await ethers.provider.send('evm_mine', []);

      // refund loan of loanPrice / 3 (1/3 of loan price)
      await poolProxy.connect(borrower).refundLoan(tokenId, borrower.address, {
        value: loanPrice.div(3),
      });

      const lenderBalanceBefore = await ethers.provider.getBalance(lender.address);

      // get lender shares
      const lenderShares = await poolProxy.balanceOf(lender.address);

      // get lender redeem value
      const lenderRedeemValue = await poolProxy.previewRedeem(lenderShares);

      // withdraw lenderWithdrawTx liquidity
      const lenderWithdrawTx = await poolProxy
        .connect(lender)
        .redeem(lenderShares, lender.address, lender.address);

      const txLenderReceipt = await ethers.provider.getTransactionReceipt(lenderWithdrawTx.hash);
      const gasUsedLender = txLenderReceipt.gasUsed.mul(lenderWithdrawTx.gasPrice as BigNumber);

      // expect lender to have the liquidity
      const lenderBalanceAfter = await ethers.provider.getBalance(lender.address);
      expect(lenderBalanceAfter).to.be.equal(
        lenderRedeemValue.add(lenderBalanceBefore).sub(gasUsedLender),
      );

      // protocol fee collector balance before withdraw
      const protocolFeeCollectorBalanceBefore = await ethers.provider.getBalance(
        protocolFeeCollector.address,
      );

      // withdraw protocol fees
      const protocolCollectorShares = await poolProxy.balanceOf(protocolFeeCollector.address);
      const totalFeesCollectedInAssets = await poolProxy.previewRedeem(protocolCollectorShares);

      const withdrawTx = await poolProxy
        .connect(protocolFeeCollector)
        .redeem(
          protocolCollectorShares,
          protocolFeeCollector.address,
          protocolFeeCollector.address,
        );

      // expect protocol fees to be 0 after withdraw
      const totalFeesCollectedAfterWithdraw = await poolProxy.balanceOf(
        protocolFeeCollector.address,
      );
      expect(totalFeesCollectedAfterWithdraw).to.be.equal(0);

      // expect protocol fee collector to have the protocol fees
      const protocolFeeCollectorBalanceAfter = await ethers.provider.getBalance(
        protocolFeeCollector.address,
      );

      const txReceipt = await ethers.provider.getTransactionReceipt(withdrawTx.hash);
      const gasUsed = txReceipt.gasUsed.mul(withdrawTx.gasPrice as BigNumber);

      expect(protocolFeeCollectorBalanceAfter).to.be.equal(
        totalFeesCollectedInAssets.add(protocolFeeCollectorBalanceBefore).sub(gasUsed),
      );

      const poolCreatorBalanceInShares = await poolProxy.balanceOf(poolFactoryOwner.address);
      const poolCreatorBalanceInAssets = await poolProxy.previewRedeem(poolCreatorBalanceInShares);
      const poolCreatorBalanceBefore = await ethers.provider.getBalance(poolFactoryOwner.address);

      // withdraw poolCreator
      const poolCreatorWithdrawTx = await poolProxy
        .connect(poolFactoryOwner)
        .redeem(poolCreatorBalanceInShares, poolFactoryOwner.address, poolFactoryOwner.address);

      const poolCreatorBalanceAfter = await ethers.provider.getBalance(poolFactoryOwner.address);

      const poolCreatorTxReceipt = await ethers.provider.getTransactionReceipt(
        poolCreatorWithdrawTx.hash,
      );

      const poolCreatorGasUsed = poolCreatorTxReceipt.gasUsed.mul(
        poolCreatorWithdrawTx.gasPrice as BigNumber,
      );

      expect(poolCreatorBalanceAfter).to.be.equal(
        poolCreatorBalanceInAssets.add(poolCreatorBalanceBefore).sub(poolCreatorGasUsed),
      );
    });
  });
});
