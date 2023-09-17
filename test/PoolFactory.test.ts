import { ethers } from 'hardhat';
import { expect } from 'chai';
import '@openzeppelin/hardhat-upgrades';

describe('PoolFactory', async () => {
  const buildTestContext = async () => {
    const [poolFactoryOwner, protocolFeeCollector, proxyAdmin] = await ethers.getSigners();

    const randomCollectionAddress = ethers.utils.hexlify(ethers.utils.randomBytes(20));
    const randomWrappedNFTAddress = ethers.utils.hexlify(ethers.utils.randomBytes(20));
    const randomLiquidatorAddress = ethers.utils.hexlify(ethers.utils.randomBytes(20));
    const randomNFTFilterAddress = ethers.utils.hexlify(ethers.utils.randomBytes(20));

    const loanToValueInBps = 3_000;
    const initialDailyInterestRateInBps = 50;

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

    // update collateral factory to poolFactory
    await poolFactoryProxy.updateCollateralFactory(collateralFactory.address);

    // update pool implementation to poolFactory
    await poolFactoryProxy.updatePoolImplementation(poolImpl.address);

    // update allowed ltv to poolFactory
    await poolFactoryProxy.updateallowdLTVs([loanToValueInBps]);

    // update allowed NFT filters to poolFactory
    await poolFactoryProxy.updateAllowedNFTFilters([randomNFTFilterAddress]);

    return {
      poolFactoryImpl,
      poolFactoryProxy,
      poolFactoryOwner,
      loanToValueInBps,
      randomCollectionAddress,
      initialDailyInterestRateInBps,
      randomWrappedNFTAddress,
      randomLiquidatorAddress,
      randomNFTFilterAddress,
      collateralFactory,
    };
  };
  it('should deploy PoolFactory', async () => {
    const { poolFactoryImpl } = await buildTestContext();
    expect(poolFactoryImpl.address).to.not.equal(0);
  });
  it('should be initialized', async () => {
    const { poolFactoryProxy, poolFactoryOwner } = await buildTestContext();

    expect(await poolFactoryProxy.owner()).to.equal(poolFactoryOwner.address);
  });
  it('should create a pool', async () => {
    const {
      poolFactoryProxy,
      initialDailyInterestRateInBps,
      loanToValueInBps,
      randomCollectionAddress,
      randomLiquidatorAddress,
      randomNFTFilterAddress,
    } = await buildTestContext();

    const initialDeposit = ethers.utils.parseEther('1');

    const poolProxyAddress = await poolFactoryProxy.callStatic.createPool(
      randomCollectionAddress,
      ethers.constants.AddressZero,
      loanToValueInBps,
      initialDailyInterestRateInBps,
      initialDeposit,
      randomNFTFilterAddress,
      randomLiquidatorAddress,
      { value: initialDeposit },
    );

    await poolFactoryProxy.createPool(
      randomCollectionAddress,
      ethers.constants.AddressZero,
      loanToValueInBps,
      initialDailyInterestRateInBps,
      initialDeposit,
      randomNFTFilterAddress,
      randomLiquidatorAddress,
      { value: initialDeposit },
    );

    const poolProxy = await ethers.getContractAt('Pool', poolProxyAddress);

    expect(await poolProxy.liquidator()).to.deep.equal(randomLiquidatorAddress);
    expect(await poolProxy.nftCollection()).to.deep.equal(randomCollectionAddress);
    expect(await poolProxy.NFTFilter()).to.deep.equal(randomNFTFilterAddress);
  });
});
