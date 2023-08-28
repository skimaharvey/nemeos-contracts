import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { expect } from 'chai';
import '@openzeppelin/hardhat-upgrades';
import OfferData from './fullfil-offer-data.json';
import { mockSignLoan } from './helpers';

describe('PoolFactory', async () => {
  const buildTestContext = async () => {
    const [poolFactoryOwner, protocolFeeCollector, proxyAdmin, oracleSigner, borrower] =
      await ethers.getSigners();

    const ethWhale = '0xda9dfa130df4de4673b89022ee50ff26f6ea73cf';
    const impersonatedWhaleSigner = await ethers.getImpersonatedSigner(ethWhale);

    const collecttionAddress =
      OfferData.fulfillment_data.transaction.input_data.parameters.offerToken;

    // todo: add liquidation tests
    const randomLiquidatorAddress = ethers.utils.hexlify(ethers.utils.randomBytes(20));

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

    // add pool to Collateral wrapper

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
      collecttionAddress,
      ethers.constants.AddressZero,
      loanToValueInBps,
      initialDailyInterestRateInBps,
      initialDeposit,
      nftFilterAddress,
      randomLiquidatorAddress,
      { value: initialDeposit },
    );

    await poolFactoryProxy.createPool(
      collecttionAddress,
      ethers.constants.AddressZero,
      loanToValueInBps,
      initialDailyInterestRateInBps,
      initialDeposit,
      nftFilterAddress,
      randomLiquidatorAddress,
      { value: initialDeposit },
    );

    const poolProxy = Pool.attach(poolProxyAddress);

    return {
      poolFactoryImpl,
      poolFactoryProxy,
      poolFactoryOwner,
      loanToValueInBps,
      collecttionAddress,
      initialDailyInterestRateInBps,
      randomLiquidatorAddress,
      nftFilterAddress,
      collateralFactory,
      poolProxy,
      impersonatedWhaleSigner,
      seaportSettlementManager,
      oracleSigner,
      borrower,
    };
  };

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
  it('should be able to buy NFT from Seaport', async () => {
    const {
      poolProxy,
      impersonatedWhaleSigner,
      initialDailyInterestRateInBps,
      seaportSettlementManager,
      nftFilterAddress,
      loanToValueInBps,
      collecttionAddress,
      oracleSigner,
      borrower,
    } = await buildTestContext();

    const nftPrice = OfferData.fulfillment_data.transaction.value;
    const ltvValue = (nftPrice * loanToValueInBps) / 10000 + 1;

    // get block timestamp
    const block = await ethers.provider.getBlock('latest');
    const loanTimestamp = block.timestamp;

    const loanDurationInDays = 30;
    const loanDurationInSeconds = loanDurationInDays * 24 * 60 * 60;

    const maxLoanAmount = nftPrice; // purposefully too high for tests

    const {
      considerationToken,
      considerationIdentifier,
      considerationAmount,
      offerer,
      zone,
      offerAmount,
      basicOrderType,
      startTime,
      endTime,
      zoneHash,
      salt,
      offererConduitKey,
      fulfillerConduitKey,
      totalOriginalAdditionalRecipients,
      signature,
      offerIdentifier,
    } = OfferData.fulfillment_data.transaction.input_data.parameters;

    const additionalRecipientsArray =
      OfferData.fulfillment_data.transaction.input_data.parameters.additionalRecipients.map(
        ({ amount, recipient }) => [amount, recipient],
      );

    const orderExtraDataTypes = [
      'address', // considerationToken
      'uint256', // considerationIdentifier
      'uint256', // considerationAmount
      'address', // offerer
      'address', // zone
      'uint256', // offerAmount
      'uint256', // basicOrderType
      'uint256', // startTime
      'uint256', // endTime
      'bytes32', // zoneHash
      'uint256', // salt
      'bytes32', // offererConduitKey
      'bytes32', // fulfillerConduitKey
      'uint256', // totalOriginalAdditionalRecipients
      'tuple(uint256,address)[]', // additionalRecipients
      'bytes', // signature
    ];

    const orderExtraDataValues = [
      considerationToken,
      considerationIdentifier,
      considerationAmount,
      offerer,
      zone,
      offerAmount,
      basicOrderType,
      startTime,
      endTime,
      zoneHash,
      salt,
      offererConduitKey,
      fulfillerConduitKey,
      totalOriginalAdditionalRecipients,
      additionalRecipientsArray,
      signature,
    ];

    const orderExtraData = ethers.utils.defaultAbiCoder.encode(
      orderExtraDataTypes,
      orderExtraDataValues,
    );

    const oracleSignature = await mockSignLoan(
      collecttionAddress,
      offerIdentifier,
      BigNumber.from(nftPrice.toString()),
      borrower.address,
      0,
      loanTimestamp,
      orderExtraData,
      oracleSigner,
    );

    const deposit = ethers.utils.parseEther('100');
    await poolProxy
      .connect(impersonatedWhaleSigner)
      .depositNativeTokens(impersonatedWhaleSigner.address, initialDailyInterestRateInBps, {
        value: deposit,
      });

    // buy NFT
    const tx = await poolProxy
      .connect(borrower)
      .buyNFT(
        collecttionAddress,
        offerIdentifier,
        BigNumber.from(nftPrice.toString()),
        seaportSettlementManager.address,
        loanTimestamp,
        loanDurationInSeconds,
        BigNumber.from(maxLoanAmount.toString()),
        orderExtraData,
        oracleSignature,
        { value: BigNumber.from(ltvValue.toString()) },
      );

    await expect(tx).to.emit(seaportSettlementManager, 'BuyExecuted');
  });
});
